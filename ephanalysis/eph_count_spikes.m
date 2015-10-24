function [num_spikes, spike_time, spike_heights] = eph_count_spikes(Vs, ts, varargin)
% Count the number of spikes given a time series
%
% [num_spikes, spike_time, spike_heights] = detect_spikes(Vs, option1, val1, ...)
%
% Inputs:
%   Vs: voltage time series, N x M matrix with N time points and M trials 
%       in units of [mV].
%   ts: sampling rate [seconds]
%
%   Optional criteria to select spikes, following arguments of FINDPEAKS 
%   function. Options include the following: 
%           'MINPEAKHEIGHT', MPH: spikes need to be above MPH
%           'MINPEAKDISTANCE, MPD: neighboring spikes need to be MPD apart.
%                            Note that this is in seconds, instead of
%                            number of indices for FINDPEAKS.
%           'THRESHOLD', TH: inds peaks that are at least greater than 
%                            their neighbors by the THRESHOLD TH.
%           'NPEAKS', NP: maximum number of peaks to find
%
%   Default: {'MINPEAKHEIGHT', -10}
%
% Outpus:
%   num_spikes: number of spikes for each trial
%   spike_time: indices of the spike, returned as one cell array of time
%           vectors per trial
%   spike_heights: voltage of the spike [mV], returned as one cell array
%           of spike heights per trial
%
% Depends on EPH_IND2TIME, FINDPEAKS

if nargin<2 || isempty(varargin)
    varargin = {'MINPEAKHEIGHT', -10};
else
    IND = find(ismember(varargin(1:2:end), 'MINPEAKDISTANCE'),1);
    if ~isempty(IND)
        varargin{IND*2} = eph_time2ind(varargin{IND*2}, ts);
    end
end
% find spikes
numTrials = size(Vs,2);
spike_heights = cell(1,numTrials);
spike_time = cell(1,numTrials);
for m = 1:numTrials
    [spike_heights{m}, spike_time{m}] = findpeaks(Vs(:,m), varargin{:});
end
num_spikes = cellfun(@numel, spike_time);
spike_time = cellfun(@(x) eph_ind2time(x,ts), spike_time, 'un',0);
if numel(spike_time) == 1
    spike_time = spike_time{1}; 
    spike_heights = spike_heights{1};
end
end