function cast = read_castaway(csvfile)
%READ_CASTAWAY Read one processed SonTek CastAway CTD cast (.csv).
%
%   CAST = READ_CASTAWAY(CSVFILE) reads the '% key,value' header and the
%   data table of a CastAway export and returns a struct with
%
%       file      - file name (no folder)
%       time      - cast time (UTC), datetime
%       lat, lon  - start position of the cast (deg)
%       depth     - depth (m), column, increasing
%       temp      - temperature (deg C)
%       sal       - salinity (PSU)
%       c         - sound speed (m/s) as computed by the CastAway
%       density   - density (kg/m^3)
%
%   Duplicate depths are averaged so DEPTH is strictly increasing.
%
%   See also LOAD_SITE_SVPS.

fid = fopen(csvfile, 'r');
if fid < 0
    error('read_castaway:open', 'Cannot open %s', csvfile);
end
cleanup = onCleanup(@() fclose(fid));

hdr = struct();
nhdr = 0;
while true
    l = fgetl(fid);
    if ~ischar(l), break; end
    if startsWith(l, '%')
        nhdr = nhdr + 1;
        kv = split(string(strtrim(extractAfter(l, 1))), ',');
        if numel(kv) >= 2 && strlength(kv(1)) > 0
            hdr.(matlab.lang.makeValidName(kv(1))) = kv(2);
        end
    else
        break; % column header line
    end
end
clear cleanup

opts = detectImportOptions(csvfile, 'NumHeaderLines', nhdr, 'VariableNamingRule', 'preserve');
T = readtable(csvfile, opts);
names = T.Properties.VariableNames;
col = @(pat) T{:, find(contains(names, pat, 'IgnoreCase', true), 1)};

[~, f, e] = fileparts(csvfile);
cast.file = [f e];
cast.time = datetime(hdr.CastTime_UTC_, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
cast.lat = str2double(hdr.StartLatitude);
cast.lon = str2double(hdr.StartLongitude);

z = col('Depth');
vars = {col('Temperature'), col('Salinity'), col('Sound velocity'), col('Density')};
ok = isfinite(z) & z >= 0;
[zu, ~, g] = unique(z(ok));
cast.depth = zu(:);
v = cellfun(@(x) accumarray(g, x(ok), [], @mean), vars, 'UniformOutput', false);
[cast.temp, cast.sal, cast.c, cast.density] = v{:};
end
