function simg = mipgibbs2d2r(gimg,simg,beta,numOfIteration)

% MIPGIBBS2D2R  MRF based segmentation
%
%   SIMG = MIPGIBBS2D2R(IMG,SIMG,BETA,NOOFITERATION)
%
% img       : input image
% simg      : initial segmentation
% beta      : Beta
% noOfIteration     : number of iteration

%
% simg      : output image
%
%   See also MIPICM2DMR  MIPICM2D2R MIPMETROPOLIS2D2R MIPMETROPOLIS2DMR
%            MIPICM3D

%   Omer Demirkaya, Musa Asyali, Prasana Shaoo, ... 9/1/06
%   Medical Image Processing Toolbox


% Replicate the images edges
gimg = padarray(gimg,[1 1],'replicate','both');
simg = padarray(simg,[1 1],'replicate','both');
[row, col] = size(gimg);
% Initilize the parameters
T = 4; C = 0.97; k = 0;
% Caculate region statistics
[mus, sigs] = mipregionstats(gimg(2:end-1,2:end-1),...
    simg(2:end-1,2:end-1),2);
vars = (sigs + 0.01).^2;
while (k <= numOfIteration)
    % Random numbers from uniform distribution and take the log
    U = random('Uniform', 0, 1, row,col);
    % raster scan the image
    for i = 2:row-1
        for j = 2:col-1
            s = simg(i,j);
            r = 3 - s;
            e1 = mipTotalEnergy(gimg,simg,mus,vars,i,j,s,beta);
            e2 = mipTotalEnergy(gimg,simg,mus,vars,i,j,r,beta);
            if U(i,j) <= exp(-e2)/(exp(-e1/T) + exp(-e1/T))
                simg(i,j) = r;
            end
        end
    end
    T = T*C; k = k + 1;
    [mus, sigs] = mipregionstats(gimg(2:end-1,2:end-1),...
        simg(2:end-1,2:end-1),2);
    vars = (sigs + 0.01).^2;
end
simg = simg(2:end-1,2:end-1);