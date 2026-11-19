function casts = load_site_svps(svpfolder, sitelatlon, varargin)
%LOAD_SITE_SVPS Load CastAway casts and grid their sound speed profiles.
%
%   CASTS = LOAD_SITE_SVPS(SVPFOLDER, SITELATLON) reads every CastAway
%   .csv in SVPFOLDER (see READ_CASTAWAY) and returns them as a struct
%   array, sorted by time, with these fields added:
%
%       dist   - distance of the cast from SITELATLON [lat lon] (m)
%       zgrid  - regular depth grid from the surface to 'seabed' (m)
%       cgrid  - sound speed on ZGRID (m/s): bin averaged, with the top and
%                bottom values held constant where the cast did not reach
%       maxz   - deepest sample of the cast (m)
%
%   Name-value options:
%       'seabed' - depth the profiles are extended to (m) [17.2]
%       'dz'     - grid spacing (m) [0.5]
%
%   See also READ_CASTAWAY, ACTUP_TRACE_RAYS.

p = inputParser;
p.addParameter('seabed', 17.2);
p.addParameter('dz', 0.5);
p.parse(varargin{:});
opt = p.Results;

files = dir(fullfile(svpfolder, '*.csv'));
if isempty(files)
    error('load_site_svps:none', 'No CastAway .csv files in %s', svpfolder);
end

zgrid = (0:opt.dz:opt.seabed)';
if zgrid(end) < opt.seabed
    zgrid(end+1) = opt.seabed;
end

for i = numel(files):-1:1
    c = read_castaway(fullfile(files(i).folder, files(i).name));
    c.dist = distance_m(c.lat, c.lon, sitelatlon(1), sitelatlon(2));
    c.maxz = max(c.depth);
    % bin average onto the grid, then fill gaps by interpolation and hold
    % the end values constant (surface few cm and below the deepest sample)
    edges = [zgrid - opt.dz/2; zgrid(end) + opt.dz/2];
    bin = discretize(c.depth, edges);
    ok = ~isnan(bin);
    cb = accumarray(bin(ok), c.c(ok), [numel(zgrid) 1], @mean, NaN);
    good = ~isnan(cb);
    if sum(good) < 2
        cb(:) = mean(c.c);
    else
        cb = interp1(zgrid(good), cb(good), zgrid, 'linear');
        cb(zgrid < min(zgrid(good))) = cb(find(good, 1, 'first'));
        cb(zgrid > max(zgrid(good))) = cb(find(good, 1, 'last'));
    end
    c.zgrid = zgrid;
    c.cgrid = cb;
    casts(i) = c; %#ok<AGROW>
end
[~, k] = sort([casts.time]);
casts = casts(k);
end

function d = distance_m(lat1, lon1, lat2, lon2)
% haversine distance (m)
R = 6371000;
dlat = deg2rad(lat2 - lat1);
dlon = deg2rad(lon2 - lon1);
a = sin(dlat/2).^2 + cos(deg2rad(lat1)).*cos(deg2rad(lat2)).*sin(dlon/2).^2;
d = 2*R*asin(sqrt(a));
end
