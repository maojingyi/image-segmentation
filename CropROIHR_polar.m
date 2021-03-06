%this is the version for cropping ROIs of STORM image using coordinates of
%centers from other methods (uses variable 'coords' from HistTxt2D,
%otherwise explicity declare 'coords' as [X;Y] Nx2 matrix before running)
%also crops and aligns .dax file
% function CropROIHR(X)
clearvars -except coords
load('svm_conv')
addpath ../common
addpath ../ransac
%load parameter vector for structure classification
load('theta_opt_070317.mat');

AverageMode=1;
ConvMatchMode=1;
ConvThresh=1000;
%for avg. and stdev of Z
SaveData=1;
%ROIWidth should be even

ROIWidth=6;

ROIWidth_Z = 2; %px, *160 to get nm - can use any decimal number
% for Z statistics of smaller ROI in center
ROIWidth_Z_half = ROIWidth_Z/2;
ROIHalf=ROIWidth/2;
offset=10;
scale=10;

ROIWidthScale=ROIWidth*scale;
%-0.5 to account for pixel vs matrix indexing mismatch
offsetScale=((offset-0.5)*scale-ROIWidthScale/2);

% map
if exist('LastFolder','var')
    GetFileName=sprintf('%s/*.bin',LastFolder);
else
    GetFileName='*.bin';
end



[FileNameL,PathNameL] = uigetfile(GetFileName,'Select the STORM bin file to crop');
LastFolder=PathNameL;

GetFileName=sprintf('%s/*.dax',LastFolder);
[FileNameDax,PathNameDax] = uigetfile(GetFileName,'Select dax file');

if ~FileNameDax
    dax=0;
else
    dax =sprintf('%s%s',PathNameDax,FileNameDax);
    InfName = dax(1:end-4);
    inf = sprintf('%s.inf',InfName);
    movie=ReadDax(dax);
    info=ReadInfoFile(inf);
    movieScale=imresize(movie,scale);
    
end

% GetFileName=sprintf('%s/*.inf',LastFolder);
% GetFileName=sprintf('%s/*.inf',LastFolder);
% [FileNameInf,PathNameInf] = uigetfile(GetFileName,'Select inf file');


LeftFile =sprintf('%s%s',PathNameL,FileNameL);
if LeftFile(end-2)=='b'
    list_left = readbinfileNXcYcZc(LeftFile);
else
    list_left=readbintext(LeftFile);
end

filehead = LeftFile(1:end-4);
Lx=list_left.xc;
Ly=list_left.yc;
LxN=Lx;
LyN=Ly;
Frame=list_left.frame;

Rx=coords(:,1);
Ry=coords(:,2);


Cat2IndFinal=[];
Cat3IndFinal=[];
radius_out=[];
CoeffInd=[];
if ~~dax
    MovSize=size(movie);
    NewMov=[];
    NewMov_match=[];
end

%% initialize data matrix for indexing
m=StructToMat(list_left);
data_final=[];
data_final_match=[];
Stats_List = zeros(numel(Rx),6);
radius_List = zeros(numel(Rx),1);
z_quantile_cat1 = zeros(numel(Rx),4);
z_quantile_cat2 = zeros(numel(Rx),4);
quantile_list = [0.05 0.1 0.9 0.95];
frame_count=1;
frame_count_match=1;
match_list_ind = [];
%%
for i=1:numel(Rx)
    
    
    fprintf('Cropping %d of %d\n',i,numel(Rx))
    XMax=Rx(i)+ROIHalf;
    XMin=Rx(i)-ROIHalf;
    YMax=Ry(i)+ROIHalf;
    YMin=Ry(i)-ROIHalf;
    ROIInd=find(Lx>XMin&Lx<XMax&Ly>YMin&Ly<YMax);
    data_now = m(ROIInd,:);
    
    if SaveData==1
        % for Z statistics of smaller ROI in center
        XMaxZ=Rx(i)+ROIWidth_Z_half;
        XMinZ=Rx(i)-ROIWidth_Z_half;
        YMaxZ=Ry(i)+ROIWidth_Z_half;
        YMinZ=Ry(i)-ROIWidth_Z_half;


        ROIInd_Z_Cat1=find(data_now(:,2)>XMinZ&data_now(:,2)<XMaxZ&data_now(:,3)>YMinZ&data_now(:,3)<YMaxZ&data_now(:,1)==1);
        ROIInd_Z_Cat2=find(data_now(:,2)>XMinZ&data_now(:,2)<XMaxZ&data_now(:,3)>YMinZ&data_now(:,3)<YMaxZ&data_now(:,1)==2);
%         Cat1Ind_now = find(data_now(:,1)==1);
%         Cat2Ind_now = find(data_now(:,1)==2);
        Z = data_now(:,4);
        zCat1 = Z(ROIInd_Z_Cat1);
        zCat2 = Z(ROIInd_Z_Cat2);
        zSort1 = sort(zCat1);
        zSort2 = sort(zCat2);
        num_z1 = numel(zCat1);
        num_z2 = numel(zCat2);
        
        for j=1:numel(quantile_list)
            if num_z1>100&num_z2>100
                z_quantile_cat1(i,j) = zSort1(round(quantile_list(j)*num_z1));
                z_quantile_cat2(i,j) = zSort2(round(quantile_list(j)*num_z2));
            else
                z_quantile_cat1(i,j) = 0;
                z_quantile_cat2(i,j) = 0;
            end
        end
        
        Stats_List(i,:) = [mean(zCat1), median(zCat1), std(zCat1), mean(zCat2), median(zCat2) std(zCat2)];
        %assign to cat 3+4
%         data_now(ROIInd_Z_Cat1,1)=3;
%         data_now(ROIInd_Z_Cat2,1)=4;
    end
    
    if AverageMode==1
        xCenter=Rx(i);
        yCenter=Ry(i);
        
        LxNow=Lx(ROIInd)-Rx(i);
        LyNow=Ly(ROIInd)-Ry(i);
%         
        data_now(:,2)=data_now(:,2)-xCenter+offset;
        data_now(:,3)=data_now(:,3)-yCenter+offset;     
        data_now(:,5)=data_now(:,5)-xCenter+offset;
        data_now(:,6)=data_now(:,6)-yCenter+offset; 
        CatNow=data_now(:,1);
                
        %find all cat 2 for structure classification - 2 for clathrin
        idx_use_classifier=find(CatNow==2);
        x_use_classifier = data_now(idx_use_classifier,2);
        y_use_classifier = data_now(idx_use_classifier,3);
        
        %get parameters for binary classifier
        list_num = numel(idx_use_classifier);
%         [t_hist, r_hist, center, score, radius] = ransac_ring(x_use_classifier,y_use_classifier);
%         train_Now = [score; radius; list_num; center';...
%                     t_hist'; r_hist'; std(t_hist)/mean(t_hist);...
%                     std(r_hist)/mean(r_hist)];
%         
%         
%         [t_hist, r_hist, center, score, radius] = ransac_ring(x_use_classifier,y_use_classifier);
        train_Now = parameterize_ROI(x_use_classifier,y_use_classifier);
        classifier_parameters(:,i) = train_Now;

        
%         [rad_out] = polar2(LxNow,LyNow,xCenter,yCenter,CatNow);
%         radius_List(i) = rad_out;
        daxCenter=[Ry(i),Rx(i)];
        daxCenterScale=round(daxCenter*scale);
        
        %find intensity of conv image at center
        intensity=0;
        if ~~dax
            intensity=movieScale(daxCenterScale(1),daxCenterScale(2));
            daxLoc=[daxCenterScale+ROIWidthScale/2; daxCenterScale-ROIWidthScale/2];
            movieROI=movieScale(daxLoc(2,1):daxLoc(1,1),daxLoc(2,2):daxLoc(1,2),1);
            MovFrame=zeros(scale*MovSize(1),scale*MovSize(2));
            MovFrame(offsetScale:offsetScale+ROIWidthScale,offsetScale:offsetScale+ROIWidthScale)=movieROI;
            MovFrameI=imresize(MovFrame,1/scale);
        end
        
        
        if intensity>ConvThresh
            data_now(:,15)=frame_count_match;
            frame_count_match=frame_count_match+1;
            data_final_match = [data_final_match; data_now];
            NewMov_match = cat(3,NewMov_match,MovFrameI);
            match_list_ind_now = i;
            match_list_ind = [match_list_ind; match_list_ind_now];
        else
            data_now(:,15)=frame_count;
            frame_count=frame_count+1;
            data_final = [data_final; data_now];
            if ~~dax
                NewMov = cat(3,NewMov,MovFrameI);
            end
        end
%       need to replicate molecules into new list
%       don't need N, totalframes
%         
        
%         if R_stats(1)>20000
%             Cat3Ind=Cat2Ind;
%         end
%         stats=[stats; R_stats];
        
        Frame(ROIInd)=i;
        
    end
        
    Cat2IndFinal=[Cat2IndFinal; ROIInd];
%     Cat3IndFinal=[Cat3IndFinal; Cat3Ind];
end
fprintf('Cropping done! \rMatched ROIs: %d \rNon-matched ROIs: %d \rWriting output... \r',frame_count_match-1, frame_count-1)

%% [scores,predicted_labels] = binary_classifier(theta, classifier_parameters);
%need to load SVMModel first
[predicted_labels,scores] = predict(SVMModel,classifier_parameters');

if AverageMode==1
%taken care of when data is centered
%     list_final.x = LxN+offset;
%     list_final.y = LyN+offset;
%     list_final_match.x = LxN_match+offset;
%     list_final_match.y = LyN_match+offset;
%     Left.frame=Frame;
%     Left.cat(Cat2IndFinal)=2;
%     Left.cat(Cat3IndFinal)=3;
%     Left=StructInd(Left,Cat2IndFinal);
    outfile=sprintf('%s-CropROIs-average.bin',filehead);
    outfile_match=sprintf('%s-CropROIs-average-match.bin',filehead);
else
%     Left.cat(Cat2IndFinal)=2;
%     Left.cat(Cat3IndFinal)=3;
    outfile=sprintf('%s-CropROIs-combined.bin',filehead);
end


list_final = MatToStruct(data_final);
if ~~dax
    if ~isempty(data_final_match)
        list_final_match = MatToStruct(data_final_match);
        LxN_match = list_final_match.xc;
        LyN_match = list_final_match.yc;
        WriteMolBinNXcYcZc(list_final_match,outfile_match);
    end
end
LxN = list_final.xc;
LyN = list_final.yc;




if ~~dax
    MovSize=size(NewMov);
    MovSize_match=size(NewMov_match);
    MovSize=MovSize(3);
    %in case there's a single matched ROI
    try
        MovSize_match=MovSize_match(3);
    catch
        MovSize_match=1;
    end
    NewMov=int16(NewMov);
    NewMov_match=int16(NewMov_match);
    NewMov=abs(NewMov);
    NewMov_match=abs(NewMov_match);
end
if ~~dax
    fileheadDax = dax(1:end-4);
    DaxName=sprintf('%s-CropROIs.dax',fileheadDax);
    DaxName_match=sprintf('%s-CropROIs-match.dax',fileheadDax);
    FileNameInf=sprintf('%s.inf',FileNameDax);
    % InfName=sprintf('%s-CropROIs.inf',fileheadDax);
    % InfName_match=sprintf('%s-CropROIs-match.inf',fileheadDax);
    FileNameInfNew=sprintf('%s-CropROIs.inf',FileNameInf(1:end-4));
    FileNameInfNew_match=sprintf('%s-CropROIs-match.inf',FileNameInf(1:end-4));
    info.number_of_frames=MovSize;
    info.file=DaxName;
    info.notes=[];
    info.localName=FileNameInfNew;
    WriteDAXFiles(NewMov,info);

    info.number_of_frames=MovSize_match;
    info.file=DaxName_match;
    info.notes=[];
    info.localName=FileNameInfNew_match;
    WriteDAXFiles(NewMov_match,info);
    
%     WriteMolBinNXcYcZc(list_final_match,outfile_match);
end

WriteMolBinNXcYcZc(list_final,outfile);


%save stats list
filenameStats = sprintf('%s-stats.mat',filehead);
% filenameStats_nomatch = sprintf('%s-stats-nonmatched.mat',filehead);
Stats_List_matched = Stats_List(match_list_ind,:);
radius_List_matched = radius_List(match_list_ind,:);
radius_List_nonmatched = radius_List;
radius_List_nonmatched(match_list_ind,:) = [];
Stats_List_nonmatched = Stats_List;
Stats_List_nonmatched(match_list_ind,:) = [];
z_quantile_cat1_nonmatched = z_quantile_cat1;
z_quantile_cat2_nonmatched = z_quantile_cat2;
z_quantile_cat1_nonmatched(match_list_ind,:) = [];
z_quantile_cat2_nonmatched(match_list_ind,:) = [];
z_quantile_cat1_matched = z_quantile_cat1(match_list_ind,:);
z_quantile_cat2_matched = z_quantile_cat2(match_list_ind,:);

save(filenameStats,'Stats_List_matched','Stats_List_nonmatched','radius_List_nonmatched','radius_List_matched');

% Stats_List = Stats_List';
% filenameStats = sprintf('%s-stats.txt',filehead);
% fileID = fopen(filenameStats,'w')
% fprintf(fileID,'%6.2f %6.2f %6.2f %6.2f\r\n',Stats_List);
% fclose(fileID);