function fig = JPSTRasterOptions(action)
global rasterDisplayTrials;


switch(action)
   
case('open')
h0 = figure('Color',[0.8 0.8 0.8], ...
   'Name','Raster', ...
   'MenuBar','none', ...
	'NumberTitle','off', ...
	'Position',[300 287 169 74], ...
	'Tag','rasterOptions');
h1 = uicontrol('Parent',h0, ...
	'Units','points', ...
	'BackgroundColor',[1 1 1], ...
	'ListboxTop',0, ...
   'Position',[12 9 53.25 17.25], ...
   'String',int2str(rasterDisplayTrials), ...
	'HorizontalAlignment','right', ...
	'Style','edit', ...
	'Tag','editTrials');
h1 = uicontrol('Parent',h0, ...
	'Units','points', ...
	'BackgroundColor',[0.8 0.8 0.8], ...
	'HorizontalAlignment','left', ...
	'ListboxTop',0, ...
	'Position',[11.25 32.25 84.75 12.75], ...
	'String','show how many trials?', ...
	'Style','text', ...
	'Tag','rasterTrials');
h1 = uicontrol('Parent',h0, ...
	'Callback','JPSTRasterOptions okay', ...
	'Units','points', ...
	'ListboxTop',0, ...
	'Position',[78 9 31.5 18], ...
	'String','okay', ...
	'Tag','okay');
if nargout > 0, fig = h0; end


case('okay')
  cf = findobj('tag','editTrials');
  if ~isempty(cf)
     r = str2num(get(cf,'String'));
     if ~isempty(r)
        rasterDisplayTrials = abs(floor(r));
        if ~rasterDisplayTrials
           rasterDisplayTrials = 1;
        end   
     end   
  end
  cf = findobj('tag','rasterOptions');
  close(cf)
  
  t = ['add rasters: show first ' int2str(rasterDisplayTrials) ' trials'];
  cf = findobj('tag','raster');
  set(cf,'Label',t);

  JPSTGUI('rasterDisplay');
  cf = findobj('tag','JPSTMain');
  if isempty(cf)   
     return
  end   
  JPSTGUI('plotXHist')
  JPSTGUI('plotYHist')
  JPSTGUI('plotRast')

  
end % main switch statement
