function outData = lowPass(inData, passBand, samplingFreq)
% low pass filter data
% filteredData = lowPass(rawData, [passBandLowerLimit passBandUpperLimit], samplingFrequency)
% defaults:
%   passBand = [0.0001 150] Hz
%   samplingFrequency = 5000 Hz

if nargin < 2
    passBand = [0.0001 150];
end

if nargin < 3
    samplingFreq = 5000;
end

if size(inData, 1) > size(inData, 2)
    switchOrientation = true;
    inData = inData';
else
    switchOrientation = false;
end

if any(isnan(inData))
    nanPadded = [find(~isnan(inData), 1, 'first') - 1 length(inData) - find(~isnan(inData), 1, 'last')];
    inData = inData(~isnan(inData));
else
    nanPadded = 0;
end

filterData = lowPassFilter(passBand, samplingFreq);
outData = filter(filterData, [ones(1, numel(filterData.Numerator)*2) * inData(1) inData ones(1, numel(filterData.Numerator)*2) * inData(1)]);
outData = outData(fix(numel(filterData.Numerator)*2.5) + (1:length(inData))) + mean(inData) - mean(outData(fix(numel(filterData.Numerator)*2.5) + (1:length(inData))));

if any(nanPadded)
    outData = [nan(1, nanPadded(1)) outData nan(1, nanPadded(2))];
end

if switchOrientation
    outData = outData';
end

    function Hd = lowPassFilter(passBand, Fs)
    %
    % M-File generated by MATLAB(R) 7.0.4 and the Signal Processing Toolbox 6.3.
    % Generated on: 23-Jan-2006 17:19:18
    %
    % Equiripple Lowpass filter designed using the FIRPM function.

    Dpass = 0.057501127785;  % Passband Ripple
    Dstop = 0.0001;          % Stopband Attenuation
    dens  = 20;              % Density Factor

    % Calculate the order from the parameters using FIRPMORD.
    [N, Fo, Ao, W] = firpmord(passBand/(Fs/2), [1 0], [Dpass, Dstop]);
    % Calculate the coefficients using the FIRPM function.
    b  = firpm(N, Fo, Ao, W, {dens});
    Hd = dfilt.dffir(b);