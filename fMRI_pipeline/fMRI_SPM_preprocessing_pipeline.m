%addmatlabpkg('dicom_tools');
PIPE_dir = addmatlabpkg('fMRI_pipeline');
%addspm8;
%spm_jobman('initcfg');

% meta data for processing
base_dir = '/hsgs/projects/jhyoon1/midbrain_Stanford_3T/';

subjects{1}.name = 'M3039_CNI_052714';
subjects{1}.ref = '/hsgs/projects/jhyoon1/midbrain_Stanford_3T/ROIs/fullhead/M3039_CNI_052714_fullhead_average.nii';%needs to be ACPC aligned
subjects{1}.tasks.name = {'frac_back','mid','stop_signal','mid','RestingState'};
subjects{1}.tasks.blocks = {1:3,1:2,1:2,3:4,0};% select blocks to process
subjects{1}.tasks.TR = [3,2,2,2,3];
subjects{1}.tasks.numslices = [41,25,25,25,41];% per stack
subjects{1}.tasks.numstacks = [1,1,1,1,1];
subjects{1}.tasks.type = {'TR3','TR2','TR2','univolume','TR3'};%for average

subjects{2}.name = 'M3128_CNI_060314';
subjects{2}.ref = '/hsgs/projects/jhyoon1/midbrain_Stanford_3T/ROIs/fullhead/M3128_CNI_060314_fullhead_average.nii';%needs to be ACPC aligned
subjects{2}.tasks.name = {'frac_back','stop_signal','mid','RestingState'};
subjects{2}.tasks.blocks = {1:3,1:2,1:2,0};% select blocks to process
subjects{2}.tasks.TR = [3,2,2,3];
subjects{2}.tasks.numslices = [41,25,25,41];% per stack
subjects{2}.tasks.numstacks = [1,1,1,1];
subjects{2}.tasks.type = {'TR3','TR2','TR2','TR3'};%for average

subjects{3}.name = 'M3129_CNI_060814';
subjects{3}.ref = '/hsgs/projects/jhyoon1/midbrain_Stanford_3T/ROIs/fullhead/M3129_CNI_060814_fullhead_average.nii';%needs to be ACPC aligned
subjects{3}.tasks.name = {'frac_back','mid','stop_signal','RestingState','mid'};
subjects{3}.tasks.blocks = {1:3,1:2,1:2,0,3};% select blocks to process
subjects{3}.tasks.TR = [3,2,2,3,2];
subjects{3}.tasks.numslices = [41,25,25,41,28];% per stack
subjects{3}.tasks.numstacks = [1,1,1,1,2];
subjects{3}.tasks.type = {'TR3','TR2','TR2','TR3','mux'};%for average
subjects{3}.tasks.positionmode = {'h2f','h2f','h2f','h2f','f2h'};%acquisition direction

% directory strcucture
Dirs.funcs = 'subjects/funcs';
Dirs.movement = 'movement';
Dirs.rois = 'ROIs';
Dirs.jobs.dicom_import = 'jobfiles/dicom_import';
Dirs.jobs.preproc = 'jobfiles/preproc';
Dirs.jobs.average = 'jobfiles/average';
Dirs.jobs.smooth = 'jobfiles/smooth';
Dirs.jobs.diary = 'jobfiles/diary';
Dirs.dicoms = 'dicoms';

% start a diary to record command window
diary(fullfile(base_dir,Dirs.jobs.diary,['preprocessing_',datestr(now,'mm-dd-yyyy_HH'),'.txt']));
for n = 1:length(subjects)
    x = subjects{n};
    savename = fullfile(base_dir,Dirs.jobs.diary,[subjects{n}.name,...
        '_parameters_',datestr(now,'mm-dd-yyyy_HH'),'.mat']);
    save(savename,'-struct','x');save(savename,'Dirs','-append');clear x;
end
%% import raw data
% dicom_source = {'M3128_CNI_061314/5_1_MID_1_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_061314/6_1_MID_2_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_061314/8_1_RestingState_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_060314/5_1_Fracback_1_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_060314/6_1_Fracback_2_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_060314/7_1_Fracback_3_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_060314/9_1_StopSignal_1_BOLD_EPI_18mm_2sec',...
%     'M3128_CNI_060314/10_1_StopSignal_2_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_060814/9_1_MID_1_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_060814/10_1_MID_2_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_060814/4_1_Fracback_1_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_060814/5_1_Fracback_2_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_060814/6_1_Fracback_3_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_061114/4_1_StopSignal_1_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_061114/5_1_StopSignal_2_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_061114/9_1_RestingState_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_052714/11_1_MID_1_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_052714/12_1_MID_2_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_061014/7_1_MID_1_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_061014/8_1_MID_2_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_061014/4_1_StopSignal_1_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_061014/5_1_StopSignal_2_BOLD_EPI_18mm_2sec',...
%     'M3039_CNI_061014/10_1_RestingState_BOLD_EPI_18mm_2sec',...
%     'M3129_CNI_061114_2/4_1_MID_1_BOLD_mux2_18mm_2s'};
% func_target = {'mid/%s/M3128_CNI_060314/block1/',...
%     'mid/%s/M3128_CNI_060314/block2/',...
%     'RestingState/%s/M3128_CNI_060314/',...
%     'frac_back/%s/M3128_CNI_060314/block1/',...
%     'frac_back/%s/M3128_CNI_060314/block2/',...
%     'frac_back/%s/M3128_CNI_060314/block3/',...
%     'stop_signal/%s/M3128_CNI_060314/block1/',...
%     'stop_signal/%s/M3128_CNI_060314/block2/',...
%     'mid/%s/M3129_CNI_060814/block1/',...
%     'mid/%s/M3129_CNI_060814/block2/',...
%     'frac_back/%s/M3129_CNI_060814/block1/',...
%     'frac_back/%s/M3129_CNI_060814/block2/',...
%     'frac_back/%s/M3129_CNI_060814/block3/',...
%     'stop_signal/%s/M3129_CNI_060814/block1/',...
%     'stop_signal/%s/M3129_CNI_060814/block2/',...
%     'RestingState/%s/M3129_CNI_060814/',...
%     'mid/%s/M3039_CNI_052714/block1/',...
%     'mid/%s/M3039_CNI_052714/block2/',...
%     'mid/%s/M3039_CNI_052714/block3/',...
%     'mid/%s/M3039_CNI_052714/block4/',...
%     'stop_signal/%s/M3039_CNI_052714/block1/',...
%     'stop_signal/%s/M3039_CNI_052714/block2/',...
%     'RestingState/%s/M3039_CNI_052714/',...
%     'mid/%s/M3129_CNI_060814/block3/'};
% subset_func = [repmat({1:3},1,length(dicom_source)-1),{1:2}];
% 
% if numel(dicom_source) ~= numel(func_target)
%     error('dicom source length is not equal to funct target length');
% end
% % loop through all the files
% for n = 1:length(dicom_source)
%     orig_dcm = dicom_source{n};
%     dicom_source{n}= char(SearchFiles(fullfile(base_dir, Dirs.dicoms,dicom_source{n}),'*.nii.gz'));
%     if isempty(dicom_source{n})
%         error('cannot find dicom source %s\n', orig_dcm);
%     end
%     func_target{n} = fullfile(base_dir,sprintf(func_target{n},Dirs.funcs));
%     %eval(['!rm -rf ',func_target{n}]);
%     %ImportFuncs(dicom_source{n},func_target{n},3,'format','spm8',...
%         %'subset',subset_func{n});
% end
% % save dicom import file
% save(fullfile(base_dir,Dirs.jobs.dicom_import,[...
%     'raw_func_import_',datestr(now,'mm-dd-yyyy_HH'),'.mat']),...
%     'dicom_source','func_target','subset_func');
%% Do ACPC alignment with fullhead
%return;

%% slice timing and spatial realignment, taking average
for s = 2:length(subjects)
  [jobfiles,P] = fMRI_preprocessing(base_dir,subjects{s}.name,...
      subjects{s}.tasks,'category',Dirs,'verbose',true,'ref',...
      subjects{s}.ref);
end

%% reslice, resample, and smooth
average_names = {'TR2','TR3','mux'};%{'TR3'};% folder names under ROIs/
smooth_kernel = {[2,2,2]};%for each variant of smoothing

for s = 2:length(subjects)
    fMRI_reslice_resample_smooth(base_dir,subjects{s}.name,...
        subjects{s}.tasks,average_names,smooth_kernel,Dirs,'overwrite',false)
end
