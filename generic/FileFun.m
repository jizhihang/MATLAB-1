function FileFun(fhandle,file_list,save_dir,append_name,rm_source,varargin)
% FileFun(fhandle,file_list,save_dir,append_name,'arg1','arg2',...)
% Apply a function to a list of files or folders
% Inputs:
%   fhandle: function handle to be applied for each file. The function
%            should have input FUN(source_file, target_file)
%   file_list: list of files or folders.
%   save_dir: (optional) alternative save directory after generating
%             the new file, given the function is capable of saving files
%             elsewhere.
%             Default is the same directory as the source file_list. 
%             The input can also be a list of new file names
%             corresponding to the file list. If this is the case, the
%             length of file_listand save_dir must be the same.
%   append_name: (optional) appending the name.
%                Input is a tuple {'name',['front'/'back']}
%                where front = 1 and back = 0. For example, to append a
%                name 'resample_' before the source file name, input as
%                {'resample_','front'}. If save_dir is a list of new file 
%                names, the appendix  will still be added on the new save
%                names.
%
% WARNING: if neither save_dir nor append_name is specified, the source
%          file will be overwritten!
%
%   rm_source: (optional) [true|false] removing source file after applying 
%               the function. This gives additional options to remove 
%               source file, if specified append_name or specified save_dir
%               If append_name is AND save_dir not a list of new file names
%               empty, rm_source will be forced off. Default false.
%
% Additional arguments need only input once and will be applied to all
% the files/folders.
% 
% Examples:
%   batch reslice_nii:
%           FileFun(@reslice_nii,file_list,save_dir,{'resliced_','front'})
%   batch resample nifti to 1mm x 1mm x 1mm
%           FileFun(@resample_nii,file_list,save_dir,{'resampled_','front'},[1,1,1])


% parse inputs
if ischar(fhandle)
    %in case function is specified as a string
    fhandle = str2func(fhandle);
end
%make sure file_list is cellstr
file_list = cellstr(file_list);
flag.specified_save_dir = ~(nargin<3 | isempty(save_dir));
if ~flag.specified_save_dir
    save_dir = file_list;
elseif ischar(save_dir) && size(save_dir,1) == 1
    %could have used isdir, but this gives better feedback if save_dir
    %is not yet created
    if ~exist(save_dir,'dir')
        eval(['!mkdir -p ',save_dir]);
    end
    [~,NAME,EXT] = cellfun(@fileparts,file_list,'un',0);
    save_dir = cellfun(@(x,y) fullfile(save_dir,[x,y]),NAME,EXT,'un',0);
end
% default rm_source
if nargin<5 || isempty(rm_source)
    rm_source = false;
end
% append/prepend the name
flag.specified_append_name = (nargin>3 & ~isempty(append_name));
if flag.specified_append_name
    %check if input is cell
    if ~iscell(append_name)
        error('Input needs to be tuple/cell. See help document');
    end
    [PATHSTR,NAME,EXT] = cellfun(@fileparts,save_dir,'un',0);
    switch append_name{2}
        case 'back'%append in the back
            save_dir = cellfun(@(x,y,z) ...
                fullfile(x,[y,append_name{1},z]),PATHSTR,NAME,EXT,'un',0);
        case 'front'%prepend in the front
            save_dir = cellfun(@(x,y,z) ...
                fullfile(x,[append_name{1},y,z]),PATHSTR,NAME,EXT,'un',0);
        otherwise
            error('Unrecognized input for append_name');
    end
end

%if neither specified save_dir nor append_name
if ~flag.specified_save_dir && ~flag.specified_append_name
    rm_source = false;%do not remove source
end

% repeat the additional arguments
if ~isempty(varargin)
    argument_cell = repeat_cell(varargin,[1,length(save_dir)]);
    % apply the function to each file
    cellfun(@(x,y,z) fhandle(x,y,z{:}),file_list(:),save_dir(:),argument_cell(:));
else
    cellfun(fhandle,file_list,save_dir);
end

% remove source file if specified to do so
if rm_source
    for f = 1:length(file_list)
        eval(['!rm ', file_list{f}]);
    end
end
end

%% Sub-routine functions
function output_cell = repeat_cell(input_item,MN)
output_cell = repmat({input_item},MN(1),MN(2));
end




