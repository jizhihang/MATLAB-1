function map = colorSpread(m)
%COLORCUBE Enhanced color-cube color map.
%   COLORCUBE(M) returns an M-by-3 matrix containing a colorcube.
%   COLORCUBE, by itself, is the same length as the current colormap.
%   The colorcube contains as many regularly spaced colors in RGB
%   colorspace as possible, while attempting to provide more steps
%   of gray, pure red, pure green, and pure blue.
%
%   The algorithm for this cube was inspired by the default
%   Macintosh system colortable, and for M = 256, COLORCUBE returns
%   exactly the same colors.  For M < 8, a gray ramp of length M
%   is returned.
%
%   See also COLORMAP, RGBPLOT.

%   Copyright 1984-2006 The MathWorks, Inc. 
%   $Revision: 1.10.4.3 $  $Date: 2006/07/24 18:11:22 $

if nargin < 1, m = size(get(gcf,'colormap'),1); end

% 1: find biggest cube that can fit in less than the amount of space
%    available (if the perfect cube exactly fits, then drop down the
%    blue resolution by one, because we need extra room for the higher
%    resolution pure color ramps and gray ramp, and the eye is least
%    sensitive to blue).  But don't drop the blue resolution if it
%    is currently two - because we can't go lower than that...

nrgsteps = fix(m^(1/3)+eps) + 1;

% 2: create the colormap consisting of this cube:

rgbstep = 1/(nrgsteps-1);
[r,g,b]=meshgrid(0:rgbstep:1,0:rgbstep:1,0:rgbstep:1);
map = [r(:) g(:) b(:)];

% 3: remove gray points from white to black (ones where 3 elements
%    are equal values):

diffmap = diff(map')';
summap = sum(abs(diffmap),2);
notgrays = find(summap ~= 0);
map = map(notgrays,:);

% 4: remove pure colors (ones with two elements zero):

summap = [sum(map(:,[1 2]),2) sum(map(:,[2 3]),2) sum(map(:,[1 3]),2)];
map = map(find(min(summap,[],2) ~= 0),:);

% 5: find out how many slots are left (saving one for black)

remlen = m - size(map,1);

% 6: divide by four, and put in the biggest r, g, b and gray
%    lines that can fit in the remaining slots.  If evenly divisible,
%    each line will have same length.  If not, red/green/blue will
%    have floor(length), and gray will have the extra.

rgbnsteps = ceil(remlen / 3);

rgbstep = 1/(rgbnsteps);

rgbramp = (rgbstep:rgbstep:1)';
rgbzero = zeros(length(rgbramp), 1);

map = [map                  % cube minus r, g, b and gray ramps
    rgbramp rgbzero rgbzero % red ramp
    rgbzero rgbramp rgbzero % green ramp
    rgbzero rgbzero rgbramp]; % blue ramp


map = map(1:m, :);