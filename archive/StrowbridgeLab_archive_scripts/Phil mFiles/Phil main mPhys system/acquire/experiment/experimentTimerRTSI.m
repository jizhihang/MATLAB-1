 function experimentTimerRTSI(varargin)
% handles all data I/O using RTSI for National Instruments boards
% records episodes - experimentTimer(digStim, analogStim)
%       streams - experimentTimer('-startStream'), experimentTimer('-stopStream')
%       episode extensions - experimentTimer('-extendEpisode'),
%       episode abortions - experimentTimer('-abortEpisode'),
%       or handles seal/membrane tests, scopes, and potential tracking

% hold onto some data that we will need in the future
    persistent fifoSize         % used to make sure we don't overfill the fifo
    persistent lastReadInstructions % used to verify that the instructions of this read are the same as those of the last write (that the data represents what it is believed to)
	persistent lastWriteInstructions
	persistent streamingEpisode % TRUE if a streaming episode is being executed
	persistent lastStims        % holds last values for stims in case of extension
	
    persistent stimData         % stimulus data that was too great to fit in the FIFO when an episode was called
    persistent savedStim        % kept on hand in case the protocol requests a stim save
    persistent protocol         % protocol when the episode started
    persistent experimentInfo   % experiment when the episode started    
    persistent samplesNeeded    % number of samples needed before saving the episode
    persistent numSamples       % number of samples currently in traceData
    persistent traceData        % episode data stored from call to call
	persistent gainChannels     % keeps track of which channels are gain telegraphs
	
    persistent lastFiftyVoltages  % used to track the membrane potential
    persistent biasCurrent      % bias added for membrane potential tracking
    persistent kP               % used for Pid adjustment of holding current
    persistent iTerm            % used to keep the integral over all time of the error
    
	persistent inputResistance  % allows input resistance to be averaged over 10 trials
	persistent seriesResistance % allows series resistance to be averaged over 10 trials
    persistent lastAmpsTp       % when potential tracking is not on on any channels, set the bias of the last amp on to be 0
    
	protocolData = getappdata(0, 'currentProtocol');
    experimentHandles = get(getappdata(0, 'experiment'), 'userData');
	
	if isempty(streamingEpisode)
		streamingEpisode = 0;
    end
    if isempty(lastFiftyVoltages)
        lastFiftyVoltages = zeros(50, 1);
    end
    if isempty(fifoSize)
        adBoard = getappdata(0, 'adBoard');
        fifoSize = adBoard.analogOut.MaxSamplesQueued;
    end
	
% make sure information about the experiment and protocol are available and load it  
    if ~isappdata(0, 'experiment')
        stop(timerfind('name', 'experimentClock'));
        error('Experiment background task is being called without a valid experiment')
    end

	if ~isappdata(0, 'currentProtocol')
        stop(timerfind('name', 'experimentClock'));
        error('Experiment background task is being called without a valid protocol')
	end

% set the clocks on the experiment gui
    set(experimentHandles.cellTime, 'string', sec2time(etime(clock, get(experimentHandles.cellTime, 'userData'))));
    set(experimentHandles.episodeTime, 'string', sec2time(etime(clock, get(experimentHandles.episodeTime, 'userData'))));
    set(experimentHandles.drugTime, 'string', sec2time(etime(clock, get(experimentHandles.drugTime, 'userData'))));
  
% set some constants that we will need    
    sweepTime = 80; % msec of write time
    daScaleFactors = getappdata(0, 'daScaleFactors');
    adScaleFactors = getappdata(0, 'adScaleFactors');
    adBoard = getappdata(0, 'adBoard');        

% initialize the variables
	readInstructions = []; % channels to be read as AD channels (all whichChannels__ variables are indices into this)
	writeInstructions = [];  

% a scope can always be running so check to see if one is
	if isappdata(0, 'runningScope')
        scopeHandles = get(getappdata(0, 'runningScope'), 'userData');
        if get(scopeHandles.isRunning, 'value')
			indexValues = get(scopeHandles.channelControl(1).channel, 'userData');
			readInstructions = indexValues(cell2mat(get([scopeHandles.channelControl.channel], 'value')));
            whichChannelsRs = 1:numel(readInstructions);
			readsRemoved = [];
			for i = 1:numel(readInstructions)
				if ismember(readInstructions(i), readInstructions(1:i - 1))
					whichChannelsRs(i) = find(readInstructions(1:i - 1) == readInstructions(i));
					readsRemoved = [readsRemoved i];
				end
			end
			readInstructions(readsRemoved) = [];
        else
            whichChannelsRs = [];
        end
    else
        whichChannelsRs = [];
	end    

% an audioScope can always be running so check to see if one is
	if isappdata(0, 'audioScope')
        audioHandles = guihandles(getappdata(0, 'audioScope'));
        if get(audioHandles.isRunning, 'value')
			indexValues = get(audioHandles.leftChannel, 'userData');
			if ismember(indexValues(get(audioHandles.leftChannel, 'value')), readInstructions)
				whichChannelsAs = find(readInstructions == indexValues(get(audioHandles.leftChannel, 'value')));
			else
				readInstructions(end + 1) = indexValues(get(audioHandles.leftChannel, 'value'));
				whichChannelsAs = numel(readInstructions);
			end
			if get(audioHandles.enableStereo, 'value')
				if ismember(indexValues(get(audioHandles.rightChannel, 'value')), readInstructions)
					whichChannelsAs(end + 1) = find(readInstructions == indexValues(get(audioHandles.rightChannel, 'value')));
				else
					readInstructions(end + 1) = indexValues(get(audioHandles.rightChannel, 'value'));
					whichChannelsAs(end + 1) = numel(readInstructions);
				end
			end
        else
            whichChannelsAs = [];
        end
    else
        whichChannelsAs = [];
	end
	
% generate instructions set and stimuli for the itc18
    if nargin == 0
            if isempty(protocol)
				stimData = [];
                protocolHandles = get(getappdata(0, 'runningProtocol'), 'userData');                
                if isfield(protocolData, 'ampVoltage')
				% no episode is running so do tracking, seal/membrane tests
                   
                % determine what channels need to be recorded from or stimulated
                    whichAmpsTp = find(cell2mat(protocolData.ampTpEnable));
                    if ~isempty(whichAmpsTp)                       
                        % check to make sure we have the data to do what we want
                            for i = 1:numel(whichAmpsTp)
                                if protocolData.ampVoltage{whichAmpsTp(i)} == adBoard.numRead + 1
                                    warning(['Cannot track potential on Amp ' char(64 + i) ' since no voltage channel is indicated'])
                                    whichAmpsTp(i) = [];
                                elseif protocolData.ampStimulus{whichAmpsTp(i)} == adBoard.numWrite + 1
                                    warning(['Cannot track potential on Amp ' char(64 + i) ' since no stimulus channel is indicated'])
                                    whichAmpsTp(i) = [];
                                else
                                    % set read instruction
                                    if ismember(protocolData.ampVoltage{whichAmpsTp(i)}, readInstructions)
                                        whichChannelsTp(i) = find(readInstructions == protocolData.ampVoltage{whichAmpsTp(i)});
                                    else
                                        readInstructions(end + 1) = protocolData.ampVoltage{whichAmpsTp(i)};
                                        whichChannelsTp(i) = numel(readInstructions);
                                    end
                                    % set write instruction (assume no two amps use the same DA line
									writeInstructions(end + 1) = protocolData.ampStimulus{whichAmpsTp(i)};
                                end
                            end  
                       
                            if size(lastFiftyVoltages, 2) <  numel(whichAmpsTp)
                                lastFiftyVoltages(end, numel(whichAmpsTp)) = 0;
                            end
                        % generate the stimulus data
                            for i = 1:numel(whichAmpsTp)
                                kP(i) = protocolData.ampTpMaxPer{whichAmpsTp(i)} / 1000; % this it the input resistance in gigaohms
                                firstZero = find(lastFiftyVoltages(:, i) == 0, 1, 'first');
                                if isnan(kP(i))
                                    if firstZero < 10
                                        biasCurrent(i) = 0 * protocolData.ampBridgeBalanceStep{whichAmpsTp(i)};
                                    elseif firstZero < 30
                                        biasCurrent(i) = 0.5 * protocolData.ampBridgeBalanceStep{whichAmpsTp(i)};
                                    elseif firstZero < 50
                                        biasCurrent(i) = -0.5 * protocolData.ampBridgeBalanceStep{whichAmpsTp(i)};     
                                    else
                                        % calculate the controller constants
                                        % calculate the input resistance in gigaohms using linear least squares
                                        responses = [mean(lastFiftyVoltages(1:5,i)) mean(lastFiftyVoltages(21:26,i)) mean(lastFiftyVoltages(42:48,i))];
                                        stims = [biasCurrent(i) -biasCurrent(i) 0];
                                        
                                        % fit a line through these three points that will be the input resistance (in gigaohms)
                                        kP(i) = (numel(stims) * sum(stims .* responses) - sum(stims) * sum(responses)) / (numel(stims) * sum(stims .^2) - sum(stims)^2);
                                        set(protocolHandles.ampTpMaxPer(whichAmpsTp(i)), 'string', sprintf('%1.0f', kP(i) * 1000)); % in megaOhms
                                        iTerm(i) = 0; % integral of past activity
                                        biasCurrent(i) = 0;
                                        protocolData.ampTpMaxPer{whichAmpsTp(i)} = kP(i) * 1000;
                                        setappdata(0, 'currentProtocol', protocolData);
                                    end
                                elseif isempty(firstZero) || firstZero > 1
                                    % set currents
                                    errorValue = [protocolData.ampTpSetPoint{i}] - lastFiftyVoltages(1, i);
                                    if numel(iTerm) >= i
                                        iTerm(i) = 0.7 .* iTerm(i) + errorValue; % decaying integral term + current error
                                    else
                                        iTerm(i) = errorValue;
                                    end
                                    % do the calculation, without letting the integral component take over
                                    biasCurrent(i) = biasCurrent(i) + (0.03 .* errorValue + 0.01 .* (sign(iTerm(i)) * max([abs(iTerm(i)) 10 * abs(errorValue)]))) ./ kP(i);

                                    % check for max total current
                                    if abs(biasCurrent(i)) >= protocolData.ampTpMaxCurrent{whichAmpsTp(i)}
                                        biasCurrent(i) = sign(biasCurrent(i)) * protocolData.ampTpMaxCurrent{whichAmpsTp(i)};
                                        iTerm(i) = iTerm(i) - errorValue; % if we are not controlling the process then don't integrate the error
                                    end
                                else
                                    % set the last value saved   
                                    tempCurrentText = get(protocolHandles.ampTpCommand(whichAmpsTp(i)), 'string');
                                    biasCurrent(i) = str2double(tempCurrentText(1:end - 2));
                                end
                                set(protocolHandles.ampTpCommand(whichAmpsTp(i)), 'string', [sprintf('%0.0f', biasCurrent(i)) ' pA']);
                            end
                            stimData = repmat(biasCurrent .* daScaleFactors(whichAmpsTp), 2 * sweepTime * 1000 / protocolData.timePerPoint + 3, 1); 
                    end % potential tracking
                    
                    if ~isempty(lastAmpsTp)
                        % send a zeros stimulus to any amps on which
                        % potential tracking has been turned off
                        if exist('whichAmpsTp', 'var')
                            lastAmpsTp = setdiff(lastAmpsTp, whichAmpsTp);
                        end
                        set(protocolHandles.ampTpCommand(lastAmpsTp), 'string', '0 pA');
                        writeInstructions = [writeInstructions lastAmpsTp];
                        stimData = [stimData zeros(2 * sweepTime * 1000 / protocolData.timePerPoint + 3, numel(lastAmpsTp))];
                    end

                    if isappdata(0, 'sealTest')
                        startTime = 10; % msec
                        stopTime = 70; % msec
                        tempName = get(getappdata(0, 'sealTest'), 'name');
                        whichAmpSealTest = tempName(5) - 64;
						stepSize = protocolData.ampSealTestStep{whichAmpSealTest}; % mV
                        
                        % check to make sure we have the data that we need
                            if protocolData.ampCurrent{whichAmpSealTest} > 0 && protocolData.ampCurrent{whichAmpSealTest} == 9
                                warning(['Cannot run seal test on Amp ' char(64 + whichAmpSealTest) ' since no current channel is indicated'])
                            elseif protocolData.ampStimulus{whichAmpSealTest} > 0 && protocolData.ampStimulus{whichAmpSealTest} == 5
                                warning(['Cannot run seal test on Amp ' char(64 + whichAmpSealTest) ' since no stimulus channel is indicated'])
                            else
                                % set read instruction
                                if ismember(protocolData.ampCurrent{whichAmpSealTest}, readInstructions)
                                    whichChannelSealTest = find(readInstructions == protocolData.ampCurrent{whichAmpSealTest});                              
                                else
                                    readInstructions(end + 1) = protocolData.ampCurrent{whichAmpSealTest};
                                    whichChannelSealTest = numel(readInstructions);                              
                                end
                                % set write instruction and stimulus
                                if ismember(protocolData.ampStimulus{whichAmpSealTest}, writeInstructions)
                                    stimData(startTime * 1000 / protocolData.timePerPoint:stopTime * 1000 / protocolData.timePerPoint, find(writeInstructions == protocolData.ampStimulus{whichAmpSealTest})) = stimData(startTime * 1000 / protocolData.timePerPoint:stopTime * 1000 / protocolData.timePerPoint, find(writeInstructions == protocolData.ampStimulus{whichAmpSealTest})) + stepSize * daScaleFactors(whichAmpSealTest); %#ok<FNDSB>
                                else
                                    stimData(:, end + 1) = [zeros(startTime * 1000 / protocolData.timePerPoint - 1, 1); ones((stopTime - startTime) * 1000 / protocolData.timePerPoint + 1, 1) * stepSize * daScaleFactors(whichAmpSealTest); zeros((sweepTime - stopTime) * 1000 / protocolData.timePerPoint + 3, 1)];    
                                    writeInstructions(end + 1) = protocolData.ampStimulus{whichAmpSealTest};
                                end
                            end
                    end % seal test
                    
                    if isappdata(0, 'bridgeBalance')
                        startTime = 10; % msec
                        stopTime = 50; % msec
                        tempName = get(getappdata(0, 'bridgeBalance'), 'name');
                        whichAmpBridgeBalance = tempName(5) - 64;
						stepSize = protocolData.ampBridgeBalanceStep{whichAmpBridgeBalance}; % pA
                        
                        % check to make sure we have the data that we need
                            if protocolData.ampVoltage{whichAmpBridgeBalance} > 0 && protocolData.ampVoltage{whichAmpBridgeBalance} == 9
                                warning(['Cannot run bridge balance on Amp ' char(64 + whichAmpBridgeBalance) ' since no voltage channel is indicated'])
                            elseif protocolData.ampStimulus{whichAmpBridgeBalance} > 0 && protocolData.ampStimulus{whichAmpBridgeBalance} == 5
                                warning(['Cannot run bridge balance on Amp ' char(64 + whichAmpBridgeBalance) ' since no stimulus channel is indicated'])
                            else
                                % set read instruction
                                if ismember(protocolData.ampVoltage{whichAmpBridgeBalance}, readInstructions)
                                    whichChannelBridgeBalance = find(readInstructions == protocolData.ampVoltage{whichAmpBridgeBalance});                                 
                                else
                                    readInstructions(end + 1) = protocolData.ampVoltage{whichAmpBridgeBalance};
                                    whichChannelBridgeBalance = numel(readInstructions);                                        
                                end
                                % set write instruction and stimulus
                                if ismember(protocolData.ampStimulus{whichAmpBridgeBalance}, writeInstructions)
                                    stimData(startTime * 1000 / protocolData.timePerPoint:stopTime * 1000 / protocolData.timePerPoint, find(writeInstructions == protocolData.ampStimulus{whichAmpBridgeBalance})) = stimData(startTime * 1000 / protocolData.timePerPoint:stopTime * 1000 / protocolData.timePerPoint, find(writeInstructions == protocolData.ampStimulus{whichAmpBridgeBalance})) + stepSize * daScaleFactors(whichAmpBridgeBalance); %#ok<FNDSB>
                                else
                                    stimData(:, end + 1) = [zeros(startTime * 1000 / protocolData.timePerPoint - 1, 1); ones((stopTime - startTime) * 1000 / protocolData.timePerPoint + 1, 1) * stepSize * daScaleFactors(whichAmpBridgeBalance); zeros((sweepTime - stopTime) * 1000 / protocolData.timePerPoint + 3, 1)];    
                                    writeInstructions(end + 1) = protocolData.ampStimulus{whichAmpBridgeBalance};
                                end
                            end
                    end % seal test  
                end
			else % ~isempty(protocol)
			
				% set the scopes actual channel instead of indices
					whichChannelsRs = readInstructions(whichChannelsRs);
					whichChannelsAs = readInstructions(whichChannelsAs);

				% we are in the middle of an episode so just use last instructions
                    readInstructions = lastReadInstructions;
					writeInstructions = lastWriteInstructions;
					
                % change whichChannelsRs/As to indices of the returned data
					for i = 1:numel(whichChannelsRs)
						whichChannelsRs(i) = find(readInstructions == whichChannelsRs(i));
					end
					for i = 1:numel(whichChannelsAs)
						whichChannelsAs(i) = find(readInstructions == whichChannelsAs(i));
					end					
            end % isempty(protocol)
    else % nargin ~= 0
        if isempty(protocol) || (ischar(varargin{1}) && strcmp(varargin{1}, '-stopStream')) % only allow an episode to start if there isn't one running
            protocolHandles = get(getappdata(0, 'runningProtocol'), 'userData');
           	experimentInfo = getappdata(0, 'currentExperiment');
			
			% set the scopes to actual channels instead of indices
				whichChannelsRs = readInstructions(whichChannelsRs);
				whichChannelsAs = readInstructions(whichChannelsAs);
			
            % determine how many channels are being read and how many written
				readInstructions = [];
				for i = 1:numel(protocolHandles.channelType)
                    tempString = get(protocolHandles.channelType(i), 'string');
                    if ~iscell(tempString)
                        tempString = {tempString};
                    end
                    if ~strcmp(tempString{get(protocolHandles.channelType(i), 'value')}, 'Disabled')
						sourceData = getappdata(protocolHandles.channelType(i), 'source');
						whereComma = find(sourceData == ',', 1, 'last');
						if ~isempty(whereComma) && (strcmp(sourceData(1:3), 'AD ') || experimentInfo.ampEnable{sourceData(whereComma - 1:whereComma - 1) - 64})
							readInstructions(end + 1) = i;
						end
                    end
				end
				
				% look for simulated channels
					if isfield(protocolHandles, 'ampType')
						for i = 1:numel(protocolHandles.ampType)
							if get(protocolHandles.ampStimulus(i), 'value') < 0
								readInstructions(end + 1) = -2 * i;
								readInstructions(end + 1) = -2 * i - 1;
							end
						end
					end
				
                % change whichChannelsRs/As to indices of the returned data
					for i = 1:numel(whichChannelsRs)
						whichChannelsRs(i) = find(readInstructions == whichChannelsRs(i));
					end
					for i = 1:numel(whichChannelsAs)
						whichChannelsAs(i) = find(readInstructions == whichChannelsAs(i));
					end
%                     for i = 1:numel(whichChannelsTp)
% 						whichChannelsTp(i) = find(readInstructions == whichChannelsTp(i));
%                     end
                    
			% determine which amps have stimuli
				if isfield(experimentInfo, 'ampEnable') && sum(cell2mat(experimentInfo.ampEnable))
					whichStims = find(cell2mat(experimentInfo.ampEnable) & (cell2mat(protocolData.ampTpEnable) | cell2mat(protocolData.ampMonitorRin) | (cell2mat(protocolData.ampStimEnable) & (cell2mat(protocolData.ampStepEnable) | cell2mat(protocolData.ampPspEnable) | cell2mat(protocolData.ampSineEnable) | cell2mat(protocolData.ampCosineEnable) | cell2mat(protocolData.ampRampEnable) | cell2mat(protocolData.ampTrainEnable) | cell2mat(protocolData.ampPulseEnable) | ~cellfun('isempty', protocolData.ampMatlabStim))) | ~cellfun('isempty', protocolData.ampMatlabCommand)));
					if sum(whichStims)
						writeInstructions = [protocolData.ampStimulus{whichStims}];
					else
						writeInstructions = [];
					end
				end

			if ischar(varargin{1})
                % a stream has been requested
                    if strcmp(varargin{1}, '-startStream')
                        varargin{1} = {};
                        streamingEpisode = true;
                        samplesNeeded = inf;
                        numSamples = 0;
                        if ~isempty(writeInstructions)
                            varargin{2} = zeros(1000, numel(writeInstructions));
                        else
                            varargin{2} = {};
                        end
                    elseif strcmp(varargin{1}, '-stopStream')
						% if we were running the hardware, make sure to
						% purge any stimulus data from the FIFO
						if any(writeInstructions > 0)
							stop(ananlogIn);
                            stop(analogOut);
						end

						if numel(protocol.channelNames) > size(traceData, 2)
							protocol.channelNames(gainChannels) = [];
						end
						
                        % stop with what data we already have
                            traceData = traceData(1:numSamples, :);
                            protocol.sweepWindow = size(traceData, 1) * protocol.timePerPoint / 1000;

						% save the stimuli if requested
                            if isfield(protocol, 'ampSaveStim')
                                whichChannels = find(cell2mat(protocol.ampSaveStim));
                            else
                                whichChannels = [];
                            end
							if ~isempty(whichChannels)
								for i = 1:numel(whichChannels)
									tempChannel = find(writeInstructions == whichChannels(i), 1);
                                    if ~isempty(tempChannel)
										traceData = [traceData savedStim(1:size(traceData, 1), whichChannels(i))];
									else
										% we are trying to record a stimulus on a channel that had none
										traceData = [traceData zeros(size(traceData, 1), 1)];
                                    end
                                    if protocol.ampTypeName{whichChannels(i)}(end - 1) == 'V'
                                        protocol.channelNames{end + 1} = ['Amp ' char(whichChannels(i) + 64) ', Stim V'];
                                    else
                                        protocol.channelNames{end + 1} = ['Amp ' char(whichChannels(i) + 64) ', Stim I'];
                                    end                                    
								end
							end                
                        
						% stamp into the header the channel values
						if size(traceData, 1) >= 100
                            for i = 1:size(traceData, 2)
                                protocol.startingValues(i) = calcMean(traceData(100, i));		
                            end                            
						else
							protocol.startingValues = [];
						end
						
                        % save this to the appropriate file
                            try
								fileInfo = dir(protocol.fileName);
                                expField = fieldnames(experimentInfo);
                                for i = 1:numel(expField)
                                    protocol.(expField{i}) = experimentInfo.(expField{i});
                                end
								if numel(fileInfo) == 0
									save(protocol.fileName, 'protocol', 'traceData');
								else
									tries = 1;
									whereS = find(protocol.fileName == 'S', 1, 'last');							
									while numel(fileInfo) > 0 && tries < 100
										whereE = find(protocol.fileName == 'E', 1, 'last');
										protocol.fileName = [protocol.fileName(1:whereS) num2str(str2double(protocol.fileName(whereS + 1:whereE - 2)) + 1) protocol.fileName(whereE - 1:end)];
										fileInfo = dir(protocol.fileName);
										tries = tries + 1;
									end
									save(protocol.fileName, 'protocol', 'traceData');									
									whereE = find(protocol.fileName == 'E', 1, 'last');
									set(experimentHandles.nextEpisode, 'string', [protocol.fileName(whereS:whereE)  num2str(str2double(protocol.fileName(whereE + 1:end - 4))+1)]);
								end
							catch								
                                msgbox('There was an error writing the stream file.  The data that it contains are present as the variable traceData in the workspace you will enter when you press ok.  To save them manually you may use the file menu')
                                dbstop
                            end
                        % clean up variables
                            stimData = [];
                            experimentInfo = [];
                            samplesNeeded = [];
                            numSamples = 0;
                            traceData = [];
                            savedStim = [];
							reducedNeurons('clearStim');					
                            
                        % bring up a file browser
							fileName = protocol.fileName;
                            if ~protocol.takeImages{1}
                                fileBrowser(fileName);    
                            end
							protocol = [];   
							streamingEpisode = false;
							lastStims = [];
							set(experimentHandles.cmdStream, 'string', 'Stream');
							if strcmp(get(experimentHandles.cmdSingle, 'string'), 'Abort')
								set(experimentHandles.cmdSingle, 'string', 'Single');
								set(experimentHandles.cmdExtend, 'visible', 'off');
							end
							set(experimentHandles.progressBar, 'position', [0 0 .0001 .02], 'visible', 'on');							
                            if exist('tries', 'var')
								msgbox(['File name already in use, using ' fileName ' instead.']);
                            end
                        return
                    elseif strcmp(varargin{1}, '-abortEpisode')
                        % stop the hardware if applicable so that any
                        % stimulus left in the FIFO isn't delivered
                        stop(adBoard.analogIn);
                        stop(adBoard.analogOut);
                        return;
                    end
			else % ~ischar(varargin{1})
                % an episode has been requested

                % determine the total number of samples of output
                    samplesNeeded = (protocolData.sweepWindow * 1000 / protocolData.timePerPoint);
                    numSamples = 0;
			end % ischar(varargin{1})

            % save data about the protocol and experiment for the file header
                protocol = protocolData;
                protocol.fileName = [get(experimentHandles.mnuSetDataFolder, 'userData') filesep experimentInfo.cellName '.' datestr(clock, 'ddmmmyy') '.' experimentInfo.nextEpisode '.mat'];           
            
			% stamp into the header the channel names
				protocol.channelNames = {};
				numHits = 0;
				% add hardware channels
					for i = 1:numel(protocolHandles.channelType)
						tempString = get(protocolHandles.channelType(i), 'string');
						if ~iscell(tempString)
							tempString = {tempString};
						end
						sourceData = getappdata(protocolHandles.channelType(i), 'source');
						if ~strcmp(tempString{get(protocolHandles.channelType(i), 'value')}, 'Disabled') && (strcmp(sourceData(1:2), 'AD') || experimentInfo.ampEnable{sourceData(5) - 64})
							numHits = numHits + 1;
							indices(numHits) = i;
							protocol.channelNames{numHits} = [getappdata(protocolHandles.channelType(i), 'source') tempString{get(protocolHandles.channelType(i), 'value')}];
						end
					end

				% add software channels
                    if isfield(protocolHandles, 'ampType')
						currentFactors = getpref('amplifiers', 'currentFactors');
						for i = 1:numel(protocolHandles.ampType)
							if isnan(currentFactors{get(protocolHandles.ampType(i), 'value'), 1})
								numHits = numHits + 1;
								indices(numHits) = -2 * i;
								protocol.channelNames{numHits} = ['Amp ' char(64 + i) ' simulated V'];
								numHits = numHits + 1;
								indices(numHits) = -2 * i - 1;
								protocol.channelNames{numHits} = ['Amp ' char(64 + i) ' injected I'];
							end
						end				
                    end                    

            % if digital output is being written add that instruction
			% and generate the TTL data
                if ~isempty(varargin{1})
                    writeInstructions = [writeInstructions 6];
					
                    ttlData = zeros(size(varargin{1}, 1), 1);
                    whichTTL = 2 .^ (find(cell2mat(experimentInfo.ttlEnable)) - 1);
                    for i = 1:size(varargin{1}, 2)
                        ttlData = ttlData + varargin{1}(:,i) .* whichTTL(i);
                    end
                else
                    ttlData = [];
                end
				
            % scale DAC outs
                if ~isempty(varargin{2})
                    % save stimuli if requested
                        if isfield(protocol, 'ampSaveStim')
                            savedStim = varargin{2};
                        end                         
                    whichDAC = find(cell2mat(experimentInfo.ampEnable) & (cell2mat(protocolData.ampTpEnable) | cell2mat(protocolData.ampMonitorRin) | (cell2mat(protocolData.ampStimEnable) & (cell2mat(protocolData.ampStepEnable) | cell2mat(protocolData.ampPspEnable) | cell2mat(protocolData.ampSineEnable) | cell2mat(protocolData.ampCosineEnable) | cell2mat(protocolData.ampRampEnable) | cell2mat(protocolData.ampTrainEnable) | cell2mat(protocolData.ampPulseEnable) | ~cellfun('isempty', protocolData.ampMatlabStim))) | ~cellfun('isempty', protocolData.ampMatlabCommand)));
                    analogStim = zeros(size(varargin{2}));
					for i = 1:size(varargin{2}, 2)
						if protocolData.ampTpEnable{whichDAC(i)}
							analogStim(:,i) = (varargin{2}(:,i) + biasCurrent(find(cell2mat(protocolData.ampTpEnable)) == whichDAC(i))) .* daScaleFactors(whichDAC(i));
                        else
                            analogStim(:,i) = varargin{2}(:,i) .* daScaleFactors(whichDAC(i));                            
						end
					end
				else
					analogStim = [];
                end
                
            % add digital stimuli to analog if applicable
                stimData = [analogStim ttlData];
				
				% pad the end of the data so that when the hardware is
				% stopped there will still be data in the buffer
				padTime = 1000000 / protocol.timePerPoint;
				if numel(stimData)
					stimData(end + 1:end + padTime,:) = stimData(end * ones(padTime,1), :);
				end
                if ~isempty(stimData)
					lastStims = stimData(end, :);
				else
					lastStims = [];
                end
				
            % preallocate space for traceData
                readInstructionsH = readInstructions(readInstructions > 0);
                numChannels = numel(readInstructions);
                if ~isempty(readInstructions) && size(adScaleFactors, 2) > 1
                    for i = 1:numel(adScaleFactors)
                        if ismember(i, readInstructionsH) && ~isempty(adScaleFactors{i,2}) && ismember(adScaleFactors{i,2}, readInstructionsH)
                            numChannels = numChannels - 1;
                        end
                    end
                end            
                if isfinite(samplesNeeded)
                    traceData = nan(samplesNeeded, numChannels);
                else
                    memDetails = memory;
                    traceData = nan(min([100000000 round(memDetails.MaxPossibleArrayBytes / 9 / numChannels)]), numChannels);
                end
		elseif ischar(varargin{1}) && strcmp(varargin{1}, '-extendEpisode')
			streamingEpisode = true;
			samplesNeeded = inf;
            % preallocate space for traceData
                readInstructionsH = lastReadInstructions(lastReadInstructions > 0);
                numChannels = numel(lastReadInstructions);
                if ~isempty(readInstructionsH) && size(adScaleFactors, 2) > 1
                    for i = 1:numel(adScaleFactors)
                        if ismember(i, readInstructionsH) && ~isempty(adScaleFactors{i,2}) && ismember(adScaleFactors{i,2}, readInstructionsH)
                            numChannels = numChannels - 1;
                        end
                    end
                end            

                tempTraceData = traceData(1:numSamples, :);
                memDetails = memory;
                traceData = nan(min([100000000 round(memDetails.MaxPossibleArrayBytes / 9 / numChannels) - numel(traceData)]), numChannels);                           
                traceData(1:numSamples, :) = tempTraceData;
			return;
		else
			warning('Episode or stream already in progress')
        end
    end % nargin == 0
	
% create instructions sequence        

	% make sure we need to go further
		if isempty(readInstructions) && isempty(writeInstructions)
			% all we needed to do was update the timers
            lastReadInstructions = readInstructions;
            lastWriteInstructions = writeInstructions;            
            if strcmp(get(adBoard.analogIn, 'Running'), 'On')
                stop(adBoard.analogIn);
                flushdata(adBoard.analogIn);            
            end
			return
		end
		
	% split instructions into software and hardware
		readInstructionsH = readInstructions(readInstructions > 0);
		writeIndicesH = find(writeInstructions > 0);
		writeInstructionsH = writeInstructions(writeIndicesH);
		readIndicesS = find(readInstructions < 0);
		writeIndicesS = find(writeInstructions < 0);
        
    % assure that gain telegraph channels are being recorded
        gainChannels = [];
        indices = [];
        if ~isempty(readInstructions) && size(adScaleFactors, 2) > 1
            for i = 1:size(adScaleFactors, 1)
                if ismember(i, readInstructionsH) && ~isempty(adScaleFactors{i,2})
                    if ismember(adScaleFactors{i,2}, readInstructionsH)
                        gainChannels(end + 1) = find(readInstructionsH == adScaleFactors{i,2});
                    else
                        readInstructions(end + 1) = adScaleFactors{i,2};
                        readInstructionsH(end + 1) = adScaleFactors{i,2};
                        gainChannels(end + 1) = numel(readInstructionsH);                                                
                    end
                    indices(end + 1) = i;
                end
            end
        end        

    triggerIn = false;
	% handle hardware data acquisition if applicable
    if numel(readInstructionsH)
        if numel(readInstructions) ~= numel(lastReadInstructions)  || (numel(readInstructions) == numel(lastReadInstructions) && ~all(readInstructions == lastReadInstructions))
            % setup the hardware
            stop(adBoard.analogIn);
            flushdata(adBoard.analogIn);            
            delete(adBoard.analogIn.Channel);
            addchannel(adBoard.analogIn, readInstructionsH - 1);
            adBoard.analogIn.SamplesPerTrigger = inf;
            adBoard.analogIn.TriggerType = 'Immediate';
            adBoard.analogIn.ExternalTriggerDriveLine = 'PFI0';
            try
                set(adBoard.analogIn, 'Samplerate', 1e6 / protocolData.timePerPoint);
            catch
                error('Sampling rate not allowed')
            end                        
            % set ranges
            for i = 1:numel(readInstructionsH)
                adBoard.analogIn.Channel(i).InputRange = [-adBoard.inputRanges(protocolData.channelRange{readInstructionsH(i)}) adBoard.inputRanges(protocolData.channelRange{readInstructionsH(i)})];                
                adBoard.analogIn.Channel(i).UnitsRange = [-1000 1000];
                adBoard.analogIn.Channel(i).SensorRange = [-1 1] .* adBoard.inputRanges(protocolData.channelRange{readInstructionsH(i)}) ./ adScaleFactors{readInstructionsH(i), 1};
            end

%             start(adBoard.analogIn);
            
            triggerIn = true;         
        else
            try
                wait(adBoard.analogOut, .100); % wait for ad board to finish or for 100 ms, whichever comes first
            catch
               % wait actually throws an error if its period is reached 
            end
            numPointsRead = adBoard.analogIn.SamplesAvailable;
            if numPointsRead > 1                   
                yData = getdata(adBoard.analogIn, adBoard.analogIn.SamplesAvailable);

                % handle gain telegraphs
                    if ~isempty(gainChannels)
                        for i = 1:numel(gainChannels)
                            adScaleFactors{indices(i), 1} = adScaleFactors{indices(i), 1}(yData(end - 3, gainChannels(i)));
                        end
                    end
            else
                yData = [];
            end            
        end	
    end
    
    triggerOut = false;
    if numel(writeInstructionsH) && ~isempty(stimData)	
        if numel(writeInstructions) ~= numel(lastWriteInstructions)  || (numel(writeInstructions) == numel(lastWriteInstructions) && ~all(writeInstructions == lastWriteInstructions))
            if ~isempty(writeInstructionsH)
                stop(adBoard.analogOut);
                delete(adBoard.analogOut.Channel);
                addchannel(adBoard.analogOut, writeInstructionsH - 1);
                adBoard.analogOut.TriggerType = 'HwDigital';
                adBoard.analogOut.TriggerCondition = 'PositiveEdge';
                adBoard.analogOut.HwDigitalTriggerSource = 'PFI0';
                try
                    set(adBoard.analogOut, 'Samplerate', 1e6 / protocolData.timePerPoint);
                catch
                    error('Sampling rate not allowed')
                end
                % set ranges
                for i = 1:numel(adBoard.analogIn.Channel)
                    adBoard.analogOut.Channel(i).UnitsRange = [-10 10];
                    adBoard.analogOut.Channel(i).OutputRange = [-10 10];
                end                
            end
        end
        
        % write a stimulus if one is present
        if ~isempty(protocol) % determine whether we are running an episode
            % trim this off of the stimulus for next time
            numTrimmed = min([(adBoard.analogOut.MaxSamplesQueued - adBoard.analogOut.SamplesAvailable) / numel(writeInstructionsH) size(stimData, 1)]);

            % fill it up with stimulus
            putdata(adBoard.analogOut, stimData(1:numTrimmed, writeIndicesH)./1000);
        else
            % write the data
            try
                wait(adBoard.analogOut, .100);
            catch
                
            end
%             disp(adBoard.analogOut.SamplesAvailable)
                % It is unclear to me why the seal test jumps around so much. There are no
                % samples left in the write buffer and flushing the read immediately before
                % trigging the write does not help.
            putdata(adBoard.analogOut, stimData./1000);
        end
        if strcmp(get(adBoard.analogOut, 'Running'), 'Off')
%             start(adBoard.analogOut);
            triggerOut = true;
        end        
    end	
        
    if triggerOut
        if triggerIn
            start(adBoard.analogOut);
            start(adBoard.analogIn);
        else
            adBoard.analogOut.TriggerType = 'Immediate';
            start(adBoard.analogOut);
        end
    elseif triggerIn
        start(adBoard.analogIn);
    end
        
	% generate a value if no hardware channels being written
	if ~exist('numTrimmed', 'var')
		numTrimmed = size(stimData, 1);
	end	
	
	% handle software writes if applicable
	if numel(writeIndicesS) && numTrimmed
		reducedNeurons(char(64 + protocolData.ampCellLocation{-writeInstructions(writeIndicesS)}), stimData(1:numTrimmed, writeIndicesS), protocolData.timePerPoint / 1000, 0);
	end	

	% trim stim data
    if streamingEpisode && ~isempty(lastStims) && size(stimData, 1) < 300000 / protocol.timePerPoint
		% add a second of stim to the end
		stimData = lastStims(ones(1000000 / protocol.timePerPoint, 1), :);
		if ~isempty(savedStim)
            savedStim(end + 1:end + 1000000 / protocolData.timePerPoint, :) = lastStims(ones(1000000 / protocol.timePerPoint, 1), 1:size(lastStims, 2) - any(writeInstructionsH == 6));
		end
    end
    if numTrimmed > 0
        stimData = stimData(numTrimmed + 1:end, :);
    end
	
	% handle software reads if applicable
	if numel(readIndicesS) && numel(readInstructions) == numel(lastReadInstructions)
		if exist('yData', 'var')
			numPoints = size(yData, 1);
		else
			numPoints = 100000 / protocolData.timePerPoint;
			yData = ones(numPoints, 0);
		end

		for ampIndex = 1:abs(min(readInstructions(readIndicesS)))
			if sum(readInstructions == -2 * ampIndex) && sum(readInstructions == -2 * ampIndex - 1)
				% we are reading both channels
				[V I] = reducedNeurons(char(64 + protocolData.ampCellLocation{ampIndex}), [], protocolData.timePerPoint / 1000, numPoints);
				whichCommand = find(readInstructions == -2 * ampIndex);
				cutPoint = whichCommand - 1 - sum(readInstructions(1:whichCommand) < 0 & readInstructions(1:whichCommand) > -2 * ampIndex);
                if size(yData, 2) < cutPoint
                    cutPoint = 0;
                end
                yData = [yData(:,1:cutPoint) V yData(:, cutPoint + 1:end)];
				whichCommand = find(readInstructions == -2 * ampIndex - 1);
				cutPoint = whichCommand - 1 - sum(readInstructions(1:whichCommand) < 0 & readInstructions(1:whichCommand) > -2 * ampIndex);
				yData = [yData(:,1:cutPoint) I yData(:, cutPoint + 1:end)];							
			elseif sum(readInstructions == -2 * ampIndex)
				% we are just reading voltage
				whichCommand = find(readInstructions == -2 * ampIndex);
				cutPoint = whichCommand - 1 - sum(readInstructions(1:whichCommand) < 0 & readInstructions(1:whichCommand) > -2 * ampIndex);
				yData = [yData(:,1:cutPoint) reducedNeurons(char(64 + protocolData.ampCellLocation{ampIndex}), [], protocolData.timePerPoint / 1000, numPoints) yData(:, cutPoint + 1:end)];
			elseif sum(readInstructions == -2 * ampIndex - 1)
				% we are just reading current
				[~, I] = reducedNeurons(char(64 + protocolData.ampCellLocation{ampIndex}), [], protocolData.timePerPoint / 1000, numPoints);
				whichCommand = find(readInstructions == -2 * ampIndex - 1);
				cutPoint = whichCommand - 1 - sum(readInstructions(1:whichCommand) < 0 & readInstructions(1:whichCommand) > -2 * ampIndex);
				yData = [yData(:,1:cutPoint) I yData(:, cutPoint + 1:end)];
			else
				continue
			end		
		end
	end

	% handle figures
	if (numel(readInstructions) || numel(writeInstructions)) && numel(readInstructions) == numel(lastReadInstructions) && exist('yData', 'var') && ~isempty(yData)
        % update any scopes
		for i = 1:numel(whichChannelsRs) % won't execute if there aren't any (1:0)
            kids = get(scopeHandles.axes(i), 'children');
            tempData = get(kids(end - 2), 'ydata');
            set(kids(end - 2), 'color', 'g', 'ydata', [tempData(min([size(yData, 1) length(tempData)] + 1):end) yData(1:min([size(yData, 1) length(tempData)]), whichChannelsRs(i))']);
		end

        % update any audioScopes
		if numel(whichChannelsAs) % won't execute if there aren't any (1:0)
			if numel(whichChannelsAs) == 1
				wavplay(yData(:, whichChannelsAs) * exp(get(audioHandles.leftVolume, 'value')), 1000000/protocolData.timePerPoint, 'async');
			else
				wavplay(yData(:, whichChannelsAs) .* repmat([exp(get(audioHandles.leftVolume, 'value')) exp(get(audioHandles.rightVolume, 'value'))], size(yData, 1), 1), 1000000/protocolData.timePerPoint, 'async');			
			end
		end
		
        % store data in traceData if we are taking an episode
		if ~isempty(protocol)
			
			if exist('yData', 'var')
				% trim off any gain channels
				if exist('gainChannels', 'var')
					yData(:, gainChannels) = [];
				end

				traceData(numSamples + (1:size(yData, 1)), :) = yData;
                numSamples = numSamples + size(yData, 1);
			else
				traceData = nan(samplesNeeded,0);
                numSamples = samplesNeeded;
			end
			if isfinite(samplesNeeded)
				set(experimentHandles.progressBar, 'position', [0 0 numSamples / samplesNeeded .02]);
			else
				if strcmp(get(experimentHandles.progressBar, 'visible'), 'on')
					set(experimentHandles.progressBar, 'position', [0 0 .7 .02], 'visible', 'off');
				else
					set(experimentHandles.progressBar, 'position', [0 0 .7 .02], 'visible', 'on');
				end				
			end
			
            if numSamples >= samplesNeeded
				if exist('gainChannels', 'var')
					[whichGone whichGone] = intersect(readInstructions, readInstructionsH(gainChannels));
					protocol.channelNames(whichGone) = [];
				end
				
				% the episode is complete

				% trim off any extra time
				traceData(samplesNeeded + 1:end, :) = [];

				% save the stimuli if requested
				if isfield(protocol, 'ampSaveStim')
					whichChannels = find(cell2mat(protocol.ampSaveStim));
					if ~isempty(whichChannels)
                        for i = 1:numel(whichChannels)
							tempChannel = find(writeInstructions == protocol.ampStimulus{whichChannels(i)});
                            if ~isempty(tempChannel)
								traceData = [traceData savedStim(1:size(traceData, 1), tempChannel)];
							else
								% we are trying to record a stimulus on a channel that had none
								traceData = [traceData zeros(size(traceData, 1), 1)];
                            end
                            if protocol.ampTypeName{whichChannels(i)}(end - 1) == 'V'
                                protocol.channelNames{end + 1} = ['Amp ' char(whichChannels(i) + 64) ', Stim V'];
                            else
                                protocol.channelNames{end + 1} = ['Amp ' char(whichChannels(i) + 64) ', Stim I'];
                            end
                        end
					end
				end

				% stamp into the header the channel values
                    for i = 1:size(traceData, 2)
    					protocol.startingValues(i) = calcMean(traceData(100, i));		
                    end
                    
                % save this to the appropriate file
                    try
						fileInfo = dir(protocol.fileName);
                        expField = fieldnames(experimentInfo);
                        for i = 1:numel(expField)
                            protocol.(expField{i}) = experimentInfo.(expField{i});
                        end                        
						if numel(fileInfo) == 0
							save(protocol.fileName, 'protocol', 'traceData');
						else
							tries = 1;
							whereS = find(protocol.fileName == 'S', 1, 'last');							
							while numel(fileInfo) > 0 && tries < 100
								whereE = find(protocol.fileName == 'E', 1, 'last');
								protocol.fileName = [protocol.fileName(1:whereS) num2str(str2double(protocol.fileName(whereS + 1:whereE - 2)) + 1) protocol.fileName(whereE - 1:end)];
								fileInfo = dir(protocol.fileName);
								tries = tries + 1;
							end
							save(protocol.fileName, 'protocol', 'traceData');									
							whereE = find(protocol.fileName == 'E', 1, 'last');
							set(experimentHandles.nextEpisode, 'string', [protocol.fileName(whereS:whereE)  num2str(str2double(protocol.fileName(whereE + 1:end - 4))+1)]);
						end
                    catch
                        msgbox('There was an error writing the file.  The data that it contains are present as the variable traceData in the workspace you will enter when you press ok.  To save them manually you may use the file menu')
                        dbstop
                    end
                    
                % clean up variables
                    stimData = [];
                    experimentInfo = [];
                    samplesNeeded = [];
                    numSamples = 0;
                    traceData = [];
                    savedStim = [];
					reducedNeurons('clearStim');
                    
                % bring up a file browser
					fileName = protocol.fileName;
                    if ~protocol.takeImages{1}
                        fileBrowser(fileName);    
                    end                    
					protocol = [];    
					streamingEpisode = false;
					set(experimentHandles.cmdStream, 'string', 'Stream');
					if strcmp(get(experimentHandles.cmdSingle, 'string'), 'Abort')
						set(experimentHandles.cmdSingle, 'string', 'Single');
						set(experimentHandles.cmdExtend, 'visible', 'off');
						set(experimentHandles.progressBar, 'position', [0 0 .0001 .02], 'visible', 'on');						
					end
					if exist('tries', 'var')
						msgbox(['File name already in use, using ' fileName ' instead.']);
					end					
            end
        elseif size(yData, 1) >= sweepTime * 1000 / protocolData.timePerPoint % isempty(protocol)
            % update seal test
            if exist('whichAmpSealTest', 'var')
                figHandle = getappdata(0, 'sealTest');
                lineHandle = get(get(figHandle, 'children'), 'children');
                set(lineHandle, 'yData', yData(1:sweepTime * 1000 / protocolData.timePerPoint, whichChannelSealTest));
				if numel(inputResistance) == 10
					inputResistance = inputResistance(2:10);
					seriesResistance = seriesResistance(2:10);
				end
				inputResistance(end + 1) = stepSize / (mean(yData(stopTime * 1000 / protocolData.timePerPoint - 50:stopTime * 1000 / protocolData.timePerPoint, whichChannelSealTest)) - mean(yData(1:startTime * 1000 / protocolData.timePerPoint - 2, whichChannelSealTest))) * 1000;
				seriesResistance(end + 1) = stepSize / (max(yData(:, whichChannelSealTest)) - mean(yData(1:startTime * 1000 / protocolData.timePerPoint - 2, whichChannelSealTest))) * 1000;
                if abs(inputResistance) > 10000
                    set(figHandle, 'name', ['Amp ' char(64 + whichAmpSealTest) ', Series = ' sprintf('%4.1f', mean(seriesResistance)) 'Mohms, Input > 10 Gohms']);                				
                else
    				set(figHandle, 'name', ['Amp ' char(64 + whichAmpSealTest) ', Series = ' sprintf('%4.1f', mean(seriesResistance)) 'Mohms, Input = ' sprintf('%4.1f', mean(inputResistance)) 'Mohms']);                				
                end
            end

            % update bridge balance
            if exist('whichAmpBridgeBalance', 'var')
                figHandle = getappdata(0, 'bridgeBalance');
                lineHandle = get(get(figHandle, 'children'), 'children');
                set(lineHandle, 'yData', yData(1:sweepTime * 1000 / protocolData.timePerPoint, whichChannelBridgeBalance));
%                 set(figHandle, 'name', ['Amp ' char(64 + whichAmpBridgeBalance) ', Series = ' sprintf('%4.1f', (max(yData(:, whichChannelBridgeBalance)) - mean(yData(1:startTime - 1, whichChannelBridgeBalance))) / stepSize / 1000) 'Mohms, Input = ' sprintf('%4.1f', (mean(yData(stopTime - 10:stopTime, whichChannelBridgeBalance)) - mean(yData(1:startTime - 1, whichChannelBridgeBalance))) / stepSize / 1000) 'Mohms']);                
            end        

            if exist('whichAmpsTp', 'var') && ~isempty(whichAmpsTp)
                % we have enough so try to correct
                lastFiftyVoltages = circshift(lastFiftyVoltages, [1 0]);
                lastFiftyVoltages(1, :) = mean(yData(round(end/2:end), whichChannelsTp));                            
            end
		end
	else
		lastFiftyVoltages = [];
	end % numPointsRead > 10
        
    % save the instructions from this call so that when the data are read it is known whence they came
        lastReadInstructions = readInstructions;
		lastWriteInstructions = writeInstructions;
        if exist('whichAmpsTp', 'var')
            lastAmpsTp = whichAmpsTp;
        end