clear all;
n = 11;
Activation_Dir = 'C:\Users\Edward\Desktop\Seeded_Correlation_Maps\group_level_summary_maps\';
Template_Img = 'C:\Users\Edward\Documents\Assignments\packages\matlab_packages\spm8\templates\EPI.nii';
save_dir = 'C:\Users\Edward\Desktop\Seeded_Correlation_Maps\MosaicPlots\';
Activation_Images = {...
    'Control_SNleft_Pearson_R_map_average.nii',...
    'Control_STNleft_Pearson_R_map_average.nii',...
    'Patients_SNleft_Pearson_R_map_average.nii',...
    'Patients_STNleft_Pearson_R_map_average.nii',...
    'Control_SNleft_ZScore_map_average.nii',...
    'Control_STNleft_ZScore_map_average.nii',...
    'Patients_SNleft_ZScore_map_average.nii',...
    'Patients_STNleft_ZScore_map_average.nii',...
    'Control_SNleft_diff_Pearson_R_map_average.nii',...
    'Control_STNleft_diff_Pearson_R_map_average.nii',...
    'Patients_SNleft_diff_Pearson_R_map_average.nii',...
    'Patients_STNleft_diff_Pearson_R_map_average.nii',...
    'Control_SNleft_diff_ZScore_map_average.nii',...
    'Control_STNleft_diff_ZScore_map_average.nii',...
    'Patients_SNleft_diff_ZScore_map_average.nii',...
    'Patients_STNleft_diff_ZScore_map_average.nii',...
    'MP_RestingState_TR3_SNleft_EPI_corr_t_value_map_C_SZ_left.nii',...
    'MP_RestingState_TR3_STNleft_EPI_corr_t_value_map_C_SZ_left.nii',...
    'MP_RestingState_TR3_SNleft_EPI_corr_p_value_map_C_SZ_left.nii',...
    'MP_RestingState_TR3_STNleft_EPI_corr_p_value_map_C_SZ_left.nii'};
save_name = {'C_SN_R.tif','C_STN_R.tif',...
    'P_SN_R.tif','P_STN_R.tif','C_SN_Z.tif','C_STN_Z.tif',...
    'P_SN_Z.tif','P_STN_Z.tif',...
    'C_SN_diff_R.tif','C_STN_diff_R.tif',...
    'P_SN_diff_R.tif','P_STN_diff_R.tif','C_SN_diff_Z.tif','C_STN_diff_Z.tif',...
    'P_SN_diff_Z.tif','P_STN_diff_Z.tif',...
    'C2SZ_SN_T.tif','C2SZ_STN_T.tif',...
    'C2SZ_SN_P.tif','C2SZ_STN_P.tif'};
Title_Name = {...
    'Control SN averaged Correlation Map',...
    'Control STN averaged Correlation Map',...
    'Patient SN averaged Correlation Map',...
    'Patient STN averaged Correlation Map',...
    'Control SN averaged Z Score Map',...
    'Control STN averaged Z Score Map',...
    'Patient SN averaged Z Score Map',...
    'Patient STN averaged Z Score Map',...
    'Control SN - Background averaged Correlation Map',...
    'Control STN - Background averaged Correlation Map',...
    'Patient SN - Background averaged Correlation Map',...
    'Patient STN - Background averaged Correlation Map',...
    'Control SN - Background averaged Z Score Map',...
    'Control STN - Background averaged Z Score Map',...
    'Patient SN - Background averaged Z Score Map',...
    'Patient STN - Background averaged Z Score Map',...
    'SNleft Patient vs. Control T-value Map',...
    'STNleft Patient vs. Control T-value Map',...
    'SNleft Patient vs. Control P-value Map',...
    'STNleft Patient vs. Control P-value Map',...
    };
Threshold_list = [repmat([0.15,0.25],1,8),[1.5,1.5,0.05,0.05]];
Threshold_dir_list = [repmat({'above'},1,18),repmat({'below'},1,2)];
ColorMap_list = {[0,1],[0,1],[0,1],[0,1],[0,2],[0,2],[0,2],[0,2],...
    [0,1],[0,1],[0,1],[0,1],[0,2],[0,2],[0,2],[0,2],...
    [0,10],[0,10],[0,0.5],[0,0.5]};
ColorbarReverse_list = [false(1,18),true(1,2)];
%View = {'axial','coronal','sagittal'};
View = 'axial';
%Slice_Range = {26:2:61;30:2:85;15:2:75};%
Slice_Range = 26:2:61;
% ColorMapOpt = {'hot',[0,10],false};
% Threshold = {'above',1.5};


for n = 9:16
clear tmp;
tmp = fullfile(Activation_Dir,Activation_Images{n});
PlotOpt = {Title_Name{n},'horizontal'};
ColorMapOpt = {'hot',ColorMap_list{n},ColorbarReverse_list(n)};
Threshold = {Threshold_dir_list{n},Threshold_list(n)};
K = activationmap_mosaic(tmp,Template_Img,View,Slice_Range,...
    Threshold,PlotOpt,ColorMapOpt);
set(gcf,'units','normalized','outerposition',[0,0,1,1]);




saveas(gcf,fullfile(save_dir,save_name{n}),'tiff');
pause(2);
close all;

end