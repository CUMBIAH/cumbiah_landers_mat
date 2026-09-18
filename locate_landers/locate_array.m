%Locate the three CUMBIAH landers and plot them with bathymetry
%
% Each lander is located from the boat calibration lines with
% LOCATEPLATFORM, then the drop positions and the calculated positions are
% plotted on a surface of the seabed from the Danish KattegatSouth 50 m
% depth model, in local eastings and northings (m). Thin lines join the
% calculated positions and the legend gives the distance between each pair.
%
% A lander with a row in SETLOCATIONS is not searched for - it is put at
% that position and only the clock offset and orientation are fitted there.
% Lander 3 needs this.
%
% The bathymetry around the landers is cut out of the full grid once and
% saved to BATHYFILE, so it can be re-imported without the grid with
%
%   load(bathyfile, 'bathy')
%
% BATHY.DEPTH is in metres, negative down, on cell centres given both as
% UTM 32N (BATHY.EASTING, BATHY.NORTHING - the grid's own co-ordinates) and
% as BATHY.LAT and BATHY.LON. BATHY.R is the map raster reference.
%
% The localisation is slow so the results are kept in RESULTSFILE and only
% recalculated when the landers, set locations or depth change, or when
% RECALCULATE is true.
%
% See also LOCATE_PLATFORM, LOCATEPLATFORM, GETLANDERDATAPATHS.
clear
close all

%which deployment (1 = Oct 24, 2 = Feb 25, 3 = June 25) and which landers
deployment = 1;
landers    = [1 2 3];

depth = 17;             % depth of the landers (m), passed to LOCATEPLATFORM

boxsize    = 1000;      % bathymetry kept either side of the landers is boxsize/2 (m)
zexag      = 100;       % vertical exaggeration - the seabed here varies by ~1 m per km
plotradius = 300;       % plot +/- this many m around the landers, Inf for all the bathymetry
plotgps    = false;      % plot the boat track over the landers

recalculate    = true; % force the localisation to be run again

reextractbathy = false; % force the bathymetry to be cut out of the grid again

denmarkdir  = getlandersuperfolder();
bathygrid   = fullfile(denmarkdir, 'bathymetry', 'KattegatSouth', 'w001001.adf');
bathyfile   = fullfile(denmarkdir, 'bathymetry', sprintf('lander_array_bathymetry_dep%d.mat', deployment));
resultsfile = fullfile(denmarkdir, sprintf('lander_array_locations_dep%d.mat', deployment));

nlander = numel(landers);

%% Locate the landers

%the deployment records, for the drop positions and the GPS track
for i = 1:nlander
    [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment);
    data(i) = getlanderdatapaths(serialnumber, startTime);
end

dorecalc = recalculate || ~isfile(resultsfile);
if ~dorecalc
    cached = load(resultsfile);
    dorecalc = ~isfield(cached, 'locstable') || ~isequal(cached.landers, landers) || ...
        cached.depth ~= depth;
end

if dorecalc
    %the full LOCATEPLATFORM results are GBs (the chi2 surfaces) so they
    %stay in the workspace as RESULTS and only the positions and
    %orientation are saved, as LOCS
    keep = {'landernumber', 'location', 'locationfine', 'hprfinal', 'headingoffset', ...
        'headingstd', 'rtctimeoffset', 'chi2', 'chi2fine'};
    results = cell(1, nlander);
    locs = struct();
    for i = 1:nlander

        %main location
        % results{i} = locateplatform(data(i), 'depth', depth, 'setlocation', setloc);
        results{i} = locateplatform(data(i), 'depth', 17, 'gridlims', [-40 40], 'gridcenter', data(i).droplocation);

        for k = 1:numel(keep)
            locs(i).(keep{k}) = results{i}.(keep{k});
        end
    end
    %saved as a table, one row per lander
    locstable = struct2table(locs);
    save(resultsfile, 'locstable', 'landers', 'depth', 'deployment');
else
    locstable = cached.locstable;
    locs = table2struct(locstable);
    disp(['Loaded lander locations from ' resultsfile]);
end

%the drop and calculated positions [lat lon]. A set location is plotted as
%it was set rather than where the fine search moved it to.
droplocs = zeros(nlander, 2);
calclocs = zeros(nlander, 2);


for i = 1:nlander
    droplocs(i,:) = data(i).droplocation;
    calclocs(i,:) = locs(i).locationfine;
    fprintf('Lander %d: drop %.7f %.7f  calculated %.7f %.7f  heading, pitch, roll %s\n', ...
        landers(i), droplocs(i,:), calclocs(i,:), num2str(locs(i).hprfinal));
end

%% The bathymetry around the landers

if isfile(bathyfile) && ~reextractbathy
    load(bathyfile, 'bathy');
    disp(['Loaded bathymetry from ' bathyfile]);
else
    bathy = extractbathy(bathygrid, [droplocs; calclocs], boxsize);
    save(bathyfile, 'bathy');
    disp(['Saved bathymetry to ' bathyfile]);
end

%% Plot

%everything is plotted in metres east and north of the middle of the drop
%positions. The bathymetry is a square in UTM 32N, and the landers are
%east of that zone, so the square sits a few degrees off true north.
reflatlon = mean(droplocs, 1);

cols = getdefaultcols();

figure
hold on

[~, bx, by] = latLong2meters(reflatlon(1), reflatlon(2), bathy.lat, bathy.lon);
surf(bx, by, bathy.depth, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
colormap(bone)
cb = colorbar;
cb.Label.String = 'Depth (m)';

%colour the depths over the part that is plotted, not the whole square
inview = abs(bx) <= plotradius & abs(by) <= plotradius;
zrange = [min(bathy.depth(inview)) max(bathy.depth(inview))];
if numel(zrange) == 2 && diff(zrange) > 0
    clim(zrange)
end

%markers sit just above the seabed so the surface does not hide them
zlift = 0.3;

h = gobjects(0);
labels = {};

for i = 1:nlander
    [~, dxd, dyd] = latLong2meters(reflatlon(1), reflatlon(2), droplocs(i,1), droplocs(i,2));
    [~, dxc, dyc] = latLong2meters(reflatlon(1), reflatlon(2), calclocs(i,1), calclocs(i,2));

    zd = seabeddepth(bathy, droplocs(i,:)) + zlift;
    zc = seabeddepth(bathy, calclocs(i,:)) + zlift;

    %from where it was dropped to where it ended up
    plot3([dxd dxc], [dyd dyc], [zd zc], ':', 'Color', cols(i,:), 'LineWidth', 1.5);

    h(end+1) = plot3(dxd, dyd, zd, 'o', 'MarkerSize', 10, ...
        'MarkerEdgeColor', cols(i,:), 'LineWidth', 2);
    labels{end+1} = sprintf('Lander %d drop', landers(i));

    h(end+1) = plot3(dxc, dyc, zc, 'o', 'MarkerSize', 10, ...
        'MarkerFaceColor', cols(i,:), 'MarkerEdgeColor', 'k');
    dropdist = latLong2meters(droplocs(i,1), droplocs(i,2), calclocs(i,1), calclocs(i,2));

        labels{end+1} = sprintf('Lander %d calculated (%.1f m from drop)', landers(i), dropdist);
   
end

%thin lines between each pair of calculated positions
linestyles = {'-', '--', '-.', ':'};
pairs = nchoosek(1:nlander, 2);
for k = 1:size(pairs, 1)
    a = pairs(k,1);
    b = pairs(k,2);
    [~, dx, dy] = latLong2meters(reflatlon(1), reflatlon(2), calclocs([a b],1), calclocs([a b],2));
    dz = [seabeddepth(bathy, calclocs(a,:)) seabeddepth(bathy, calclocs(b,:))] + zlift;

    h(end+1) = plot3(dx, dy, dz, linestyles{mod(k-1, numel(linestyles))+1}, ...
        'Color', 'k', 'LineWidth', 0.75);
    d = latLong2meters(calclocs(a,1), calclocs(a,2), calclocs(b,1), calclocs(b,2));
    labels{end+1} = sprintf('Lander %d to %d: %.1f m', landers(a), landers(b), d);
end

%the boat track, draped just above the seabed and clipped to the bathymetry
if plotgps
    g = load(data(1).gpsfile);
    gpslatlon = [g.gpsdata.latitude(2:end), g.gpsdata.longitude(2:end)]; %first row is NaN
    gz = seabeddepth(bathy, gpslatlon) + zlift/2;
    inbox = ~isnan(gz);
    [~, gx, gy] = latLong2meters(reflatlon(1), reflatlon(2), gpslatlon(:,1), gpslatlon(:,2));
    gx(~inbox) = NaN;
    h(end+1) = plot3(gx, gy, gz, 'Color', [0.85 0.33 0.33 0.6], 'LineWidth', 0.5);
    labels{end+1} = 'Boat GPS';
end

legend(h, labels, 'Location', 'northeastoutside');

daspect([1 1 1/zexag])
axis tight
if isfinite(plotradius)
    xlim([-1 1]*plotradius)
    ylim([-1 1]*plotradius)
end

xlim([-100,100])
ylim([-100,100])
view(-30, 45) % view(2) for a plan view
xlabel('Eastings (m)');
ylabel('Northings (m)');
zlabel('Depth (m)');
title({sprintf('CUMBIAH landers, deployment %d', deployment), ...
    sprintf('origin %.6f N %.6f E, vertical exaggeration x%g', reflatlon, zexag)});
set(gca, 'FontSize', 14)

% ------------------------------------------------------------------------
function bathy = extractbathy(bathygrid, latlon, boxsize)
%EXTRACTBATHY Cut the bathymetry around a set of positions out of the grid.
%   LATLON is [lat lon], one row per position. The square kept is the extent
%   of the positions with BOXSIZE/2 (m) either side, in the grid's own
%   co-ordinates.

[Z, R] = readgeoraster(bathygrid);
Z(Z < -1e30) = NaN; % the ESRI no data value, in case it comes through

[x, y] = projfwd(R.ProjectedCRS, latlon(:,1), latlon(:,2));
xlims = [min(x) max(x)] + [-1 1]*boxsize/2;
ylims = [min(y) max(y)] + [-1 1]*boxsize/2;

[Zc, Rc] = mapcrop(Z, R, xlims, ylims);
[X, Y] = worldGrid(Rc);
[lat, lon] = projinv(Rc.ProjectedCRS, X, Y);

bathy.depth    = double(Zc);   % m, negative down
bathy.easting  = X;            % UTM 32N cell centres (m)
bathy.northing = Y;
bathy.lat      = lat;          % cell centres, decimal degrees WGS84
bathy.lon      = lon;
bathy.R        = Rc;           % map raster reference, for MAPINTERP etc.
bathy.crs      = 'WGS 84 / UTM zone 32N'; % from prj.adf, the grid itself has no name for it
bathy.cellsize = Rc.CellExtentInWorldX;
bathy.source   = bathygrid;
bathy.created  = datetime('now');

end

% ------------------------------------------------------------------------
function z = seabeddepth(bathy, latlon)
%SEABEDDEPTH Depth of the bathymetry at [lat lon] positions, NaN outside it.

[x, y] = projfwd(bathy.R.ProjectedCRS, latlon(:,1), latlon(:,2));
z = mapinterp(bathy.depth, bathy.R, x, y);

end
