addmatlabpkg('fMRI_pipeline');
base_dir = '/hsgs/projects/jhyoon1/midbrain_pilots/ROIs/';
ROIs = {'TR2/M3126_CNI_042514_TR2_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    'TR2/M3126_CNI_042514_TR2_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    'TR2/M3127_CNI_050214_TR2_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    'TR2/M3127_CNI_050214_TR2_ACPC_SNleft_STNleft_RNleft_VTAleft.nii'};
fnames = {'TR3/M3126_CNI_042514_FracBack_TR3_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    'TR3/M3126_CNI_042514_RestingState_TR3_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    'TR3/M3127_CNI_050214_TR3_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    'fullhead/M3127_CNI_050214_mux2_ACPC_SNleft_STNleft_RNleft_VTAleft.nii',...
    };
Template_references = {'TR3/resample_rM3126_CNI_042514_average_FracBack_TR3_brain.nii',...
    'TR3/resample_rM3126_CNI_042514_average_RestingState_TR3_brain.nii',...
    'TR3/resample_rM3127_CNI_050214_average_TR3_brain.nii',...
    'fullhead/resample_rM3127_CNI_050214_average_mux2_brain.nii'};
Template_sources = {...
'TR2/resample_rM3126_CNI_042514_average_TR2_brain.nii',...
'TR2/resample_rM3126_CNI_042514_average_TR2_brain.nii',...
'TR2/resample_rM3127_CNI_050214_average_TR2_brain.nii',...
'TR2/resample_rM3127_CNI_050214_average_TR2_brain.nii'};



for n = 1:length(ROIs)
    Auto_Coregister_ROIs(fullfile(base_dir,ROIs{n}),...
        fullfile(base_dir,Template_references{n}),...
        fullfile(base_dir,Template_sources{n}),...
        fullfile(base_dir,fnames{n}));
end