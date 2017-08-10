function zData = readTrace(filename, infoOnly)
persistent defaultProtocol
persistent defaultFields
% reads data traces generated by the data acquisition program
% zData = readTrace(fileName);
% protocol = readTrace(fileName, 1);

% display file box if no file given
if nargin == 0
    [FileName,PathName] = uigetfile({'*.mat','Data Files (*.mat)'}, 'Select file to open');
    if FileName == 0
        return
    end
    filename = strcat(PathName, FileName)
end

% check for Ben files
if filename(end - 3:end) == '.dat'
    if nargin < 2
        zData = readBen(filename);
    else
        zData = readBen(filename, infoOnly);
    end
    return
end

% load the requested data
if nargin < 2 || infoOnly == 0
	zData = load(filename);
    if isfield(zData, 'outData')
        zData.traceData = zData.outData;
        zData = rmfield(zData, 'outData');
    end
    if ~isfield(zData, 'protocol') || ~isfield(zData, 'traceData')
		error('Not a valid Data file')
    end
    zData.protocol.fileName = filename;
    if isfield(zData, 'experimentInfo')
        expField = fieldnames(zData.experimentInfo);
        for i = 1:numel(expField)
            zData.protocol.(expField{i}) = zData.experimentInfo.(expField{i});
        end        
    end    
    if isfield(zData, 'photometry')
        % add in photometry data
        if ischar(zData.protocol.imageDuration)
            zData.protocol.imageDuration = str2double(zData.protocol.imageDuration);
        end
        zData.protocol.photometryHeader = zData.photometryHeader;
        zData.protocol.photometryHeader.ROI = zData.ROI;
        zData.protocol.photometryHeader.data = zData.photometry;
        zData.protocol.photometryHeader.roiDelay = zData.roiDelay;
%         if ~isfield(zData, 'roiDelay')
%             roiDelay = zeros(size(zData.photometry, 2), 1);
%         end
%         stimTimes = findStims(zData.protocol, 0);
%         tempData = resample([zData.photometry(end:-1:1, :); zData.photometry; zData.photometry(end:-1:1, :)], zData.protocol.imageDuration * 1000 / zData.protocol.timePerPoint, size(zData.photometry, 1));
%         if ~isempty(stimTimes{1}) 
%             if size(tempData, 1) > 3 * size(zData.traceData, 1) + round(stimTimes{1}(:,1) + max(zData.roiDelay))
%                 % the imaging data is longer than the physiology data
%                 zData.traceData = [zData.traceData; nan(size(tempData, 1) / 3 - size(zData.traceData, 1) + round(stimTimes{1}(:,1) + max(zData.roiDelay)), size(zData.traceData, 2))];
%                 zData.protocol.sweepWindow = size(zData.traceData, 1) * zData.protocol.timePerPoint / 1000;
%             end
%             for i = 1:size(zData.photometry, 2)
%                 zData.traceData(:, end + 1) = [nan(round(stimTimes{1}(:,1) + zData.roiDelay(i)), 1); tempData(zData.protocol.imageDuration * 1000 / zData.protocol.timePerPoint + 1:2 * zData.protocol.imageDuration * 1000 / zData.protocol.timePerPoint, i); nan(size(zData.traceData, 1) - round(stimTimes{1}(:,1) + zData.protocol.imageDuration * 1000 / zData.protocol.timePerPoint + zData.roiDelay(i)), 1)];            
%                 zData.protocol.channelNames{end + 1} = ['ROI ' sprintf('%0.0f', i) ', I'];
%             end
%         end
        callStack = dbstack;
        if ~isfield(zData.protocol.photometryHeader.ROI, 'segments')
            for i = 1:numel(zData.protocol.photometryHeader.ROI)
                zData.protocol.photometryHeader.ROI(i).segments = [];
            end
        end
        if isappdata(0, 'imageBrowser') && (isappdata(0, 'fileBrowser') && numel(callStack) >= 3 && strcmp(callStack(3).file, 'fileBrowser.m') && ~strcmp(callStack(end).file, 'doSingle.m'))
            clearROI;       
            for i = 1:numel(zData.ROI)
                zData.protocol.photometryHeader.ROI(i).handle = line(nan, nan, 'parent', findobj('tag', 'imageAxis'));
            end            
            setappdata(getappdata(0, 'imageDisplay'), 'ROI', zData.protocol.photometryHeader.ROI);
            if isfield(zData.photometryHeader, 'referenceImage')
                if exist(zData.photometryHeader.referenceImage, 'file')
                    associatedImage = zData.photometryHeader.referenceImage;
                else
                    tempName = [filename(1:find(filename == filesep, 1, 'last')) zData.photometryHeader.referenceImage(find(zData.photometryHeader.referenceImage == filesep, 1, 'last') + 1:end)];
                    if exist(tempName, 'file')
                        associatedImage = tempName;
                    end
                end
                if exist('associatedImage', 'var') && isempty(strfind(get(getappdata(0, 'imageDisplay'), 'name'), associatedImage))
                    imageBrowser(associatedImage);
                end
            end
            %update the current image to show ROI
            drawROI;
            figure(getappdata(0, 'fileBrowser'));
            set(findobj('tag', 'cboRoiNumber'), 'string', num2str((1:numel(zData.ROI))'));
        end
    else
        zData.protocol.photometryHeader = [];
    end
    whatFields = fields(zData.protocol);
    if numel(whatFields) ~= 121
        if isempty(defaultProtocol)
            defaultProtocol = load('defaultProtocol.mat');
            defaultProtocol = defaultProtocol.protocol;
            defaultFields = fieldnames(defaultProtocol);
        end
        for i = setdiff(defaultFields, whatFields)'
            zData.protocol.(i{1}) = defaultProtocol.(i{1});
        end
        zData.protocol = orderfields(rmfield(zData.protocol, setdiff(whatFields, defaultFields)), defaultFields);      
    end   
else
	zData = load(filename, 'protocol');
    if ~isfield(zData, 'protocol')
		error('Not a valid Data file')
    end	
    zData = zData.protocol;
    zData.fileName = filename;
    varNames = whos('-file', filename);
    if any(strcmp({varNames.name}, 'experimentInfo'))
        load(filename, 'experimentInfo');
        expField = fieldnames(experimentInfo);
        for i = 1:numel(expField)
            zData.(expField{i}) = experimentInfo.(expField{i});
        end        
    end
    if any(strcmp({varNames.name}, 'photometryHeader'))
        temp = load(filename, 'photometryHeader');
        zData.photometryHeader = temp.photometryHeader;
        % needs to add in channel names so that we have that info
    else
        zData.photometryHeader = [];
    end
    whatFields = fields(zData);
    if isempty(defaultProtocol)
        defaultProtocol = load('defaultProtocol.mat');
        defaultProtocol = defaultProtocol.protocol;
        defaultFields = fieldnames(defaultProtocol);
    end    
    if numel(whatFields) ~= 121 || nnz(~strcmp(whatFields, defaultFields))
        for i = setdiff(defaultFields, whatFields)'
            zData.(i{1}) = defaultProtocol.(i{1});
        end
        zData = orderfields(rmfield(zData, setdiff(whatFields, defaultFields)), defaultFields);      
    end
    for i = setdiff(defaultFields, {'imageScan', 'fileName', 'nextEpisode', 'repeatInterval', 'repeatNumber', 'ampMatlabStim', 'cellName', 'channelNames', 'dataFolder', 'drug', 'ampCellLocationName', 'ampMatlabCommand', 'ttlTypeName', 'scanWhichRoi', 'sourceName', 'ampTypeName', 'ttlArbitrary', 'matlabCommand', 'bath', 'internal'})
        % some episodes got numbers saved as characters long ago
        if iscell(zData.(i{1})) && ~isempty(zData.(i{1}))
            if ischar(zData.(i{1}){1})
                for j = 1:numel(zData.(i{1}))
                    zData.(i{1}){j} = str2double(zData.(i{1}){j});
                end
            end
        else
            if ischar(zData.(i{1}))
                zData.(i{1}) = str2double(zData.(i{1}));
            end
        end
    end
    if isnumeric(zData.bath) || (iscell(zData.bath) && isnumeric(zData.bath{1}))
        zData.bath = 'Unknown';
        zData.internal = 'Unknown';
        if iscell(zData.drug)
            zData.drug = sprintf('%0.0f', zData.drug{1});
        else
            zData.drug = sprintf('%0.0f', zData.drug);
        end
    end
    if iscell(zData.ampMatlabStim{1})
        for i = 1:numel(zData.ampMatlabStim)
            zData.ampMatlabStim{i} = zData.ampMatlabStim{i}{1};
        end
    end
end

if isfield(zData, 'protocol')% && ischar(zData.protocol.ampPulse5Start{1})
    fieldNames = fieldnames(zData.protocol);

% load data from the protocol viewer
    for fieldIndex = 1:numel(fieldNames)
        if iscell(zData.protocol.(fieldNames{fieldIndex}))
            if ischar(zData.protocol.(fieldNames{fieldIndex}){1}) && ~ismember(fieldNames{fieldIndex}, {'ampCellLocationName', 'ampMatlabCommand', 'ttlTypeName', 'scanWhichRoi', 'sourceName', 'ampMatlabStim', 'ampTypeName', 'ttlArbitrary', 'channelNames'}) 
                tempData = zData.protocol.(fieldNames{fieldIndex});
                for i = 1:numel(zData.protocol.(fieldNames{fieldIndex}))
                    tempData{i} = str2double(tempData{i});
                end
                zData.protocol.(fieldNames{fieldIndex}) = tempData;
            end
        else
            if ischar(zData.protocol.(fieldNames{fieldIndex})) && ~ismember(fieldNames{fieldIndex}, {'imageScan', 'fileName', 'nextEpisode', 'matlabCommand', 'cellName', 'drug', 'bath', 'internal', 'dataFolder'})
                zData.protocol.(fieldNames{fieldIndex}) = str2double(zData.protocol.(fieldNames{fieldIndex}));
            end
        end
    end
end  