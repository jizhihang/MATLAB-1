event = 'ProbeB'
fid = fopen([event,'.csv'],'w');
load([event,'.mat']);
for n = 1:length(data)
    fprintf(fid,'%s,',data(n).subjects);
    for k = 1:length(data(n).beta_series) - 1
        fprintf(fid,'%E,',data(n).beta_series(k));
    end
    fprintf(fid,'%E',data(n).beta_series(k + 1));
    fprintf(fid,'\n')
end

    fclose('all')
    