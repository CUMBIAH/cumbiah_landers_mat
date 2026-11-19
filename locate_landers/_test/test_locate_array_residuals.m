%% Test: how well do the boat slant angles fit the lander locations?
%
% Locates every lander of the array from the boat calibration clicks with
% LOCATEPLATFORM, as LOCATE_ARRAY does (every click; the same hard coded
% database for lander 2), then for each lander:
%   - plots the slant residual (measured, with the fitted heading, pitch and
%     roll, minus the straight line slant from the fitted position) against
%     range, with its running median
%   - fits a single height of the boat noise above the hydrophones to the
%     slants within 60 m and 150 m, where refraction and the seabed echo do
%     not matter much. LOCATE_ARRAY assumes 16 m (lander at 17 m, noise 1 m
%     deep)
% and compares the positions and orientations with the saved array file.
%
% The new fit goes to a separate file in OUTFOLDER; the array file is not
% touched.
clear
close all

country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];
depth      = 17;
recalculate = false;
lander2db  = '/Users/jdjm/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander2/pamguard_michael/lander2_Denmark_database_annotated.sqlite3';
lander2bin = '/Users/jdjm/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander2/pamguard_michael/pamguard/PAMBinary';

%% Paths
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));

superfolder = getlandersuperfolder(country);
arrayfile = fullfile(superfolder, sprintf('lander_array_locations_dep%d.mat', deployment));
outfolder = fullfile(superfolder, 'propagation', 'lander_location');
if ~isfolder(outfolder), mkdir(outfolder); end
resfile = fullfile(outfolder, sprintf('locateplatform_residuals_dep%d.mat', deployment));

%% Locate
if isfile(resfile) && ~recalculate
    load(resfile, 'R', 'locstable');
else
    for i = 1:numel(landers)
        [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
        data = getlanderpaths(serialnumber, startTime);
        if landers(i) == 2 && ~isempty(lander2db)
            data.sqlitedB = lander2db;
            data.binaryfolder = lander2bin;
        end
        t0 = tic;
        res = locateplatform(data, 'depth', depth, 'gridlims', [-40 40], 'gridcenter', data.droplocation);
        fprintf('Lander %d located in %.0f s\n', landers(i), toc(t0));
        R(i) = struct('lander', landers(i), 'res', rmfield(res, {'chi2surf', 'chi2surffine'})); %#ok<SAGROW>
        locs(i) = struct('landernumber', landers(i), 'locationfine', res.locationfine, ...
            'hprfinal', res.hprfinal, 'headingstd', res.headingstd, 'rtctimeoffset', res.rtctimeoffset); %#ok<SAGROW>
    end
    locstable = struct2table(locs);
    save(resfile, 'R', 'locstable', '-v7.3');
end
saved = load(arrayfile);

%% Compare with the array file
fprintf('\n%-7s %24s %24s %8s %10s\n', 'lander', 'hpr (array file)', 'hpr (now)', 'move', 'hdg std');
for i = 1:numel(landers)
    a = saved.locstable(saved.locstable.landernumber == landers(i), :);
    b = locstable(locstable.landernumber == landers(i), :);
    d = latLong2meters(a.locationfine(1), a.locationfine(2), b.locationfine(1), b.locationfine(2));
    fprintf('%-7d %24s %24s %6.1f m %10.1f\n', landers(i), mat2str(a.hprfinal, 3), mat2str(b.hprfinal, 3), d, b.headingstd);
end
pairs = nchoosek(1:numel(landers), 2);
for q = 1:size(pairs, 1)
    i = pairs(q,1); j = pairs(q,2);
    fprintf('Landers %d-%d: %.1f m\n', landers(i), landers(j), latLong2meters(locstable.locationfine(i,1), ...
        locstable.locationfine(i,2), locstable.locationfine(j,1), locstable.locationfine(j,2)));
end

%% Residuals and the height of the boat noise
f = figure('Position', [50 50 1400 360*numel(landers)], 'Color', 'w');
tl = tiledlayout(numel(landers), 1, 'TileSpacing', 'compact');
fprintf('\nHeight of the boat noise above the hydrophones that fits the slants best (assumed %g m):\n', depth - 1);
for i = 1:numel(landers)
    res = R(i).res;
    L = locstable(i,:);
    src = res.srcclklocations;                         % datenum lat lon depth difference
    r = nan(size(src, 1), 1);
    for k = find(~any(isnan(src(:,2:3)), 2))'
        r(k) = latLong2meters(L.locationfine(1), L.locationfine(2), src(k,2), src(k,3));
    end
    meas = rad2deg(rotate_bearings(res.clkgeobearings, L.hprfinal));
    m = meas(:,2);
    resid = m - atand(src(:,4)./r);
    ax = nexttile(tl); hold(ax, 'on');
    scatter(ax, r, resid, 4, [0.5 0.5 0.5], 'filled', 'MarkerFaceAlpha', 0.2);
    edges = [0:10:100, 125:25:max(r) + 25];
    bin = discretize(r, edges);
    g = ~isnan(bin) & ~isnan(resid);
    med = accumarray(bin(g), resid(g), [numel(edges)-1 1], @median, NaN);
    plot(ax, (edges(1:end-1) + edges(2:end))/2, med, 'r-', 'LineWidth', 2.5);
    yline(ax, 0, 'k');
    set(ax, 'XScale', 'log'); xlim(ax, [5 1500]); ylim(ax, [-15 15]); grid(ax, 'on'); box(ax, 'on');
    ylabel(ax, 'Slant - straight line (deg)');
    title(ax, sprintf('Lander %d, hpr %s', landers(i), mat2str(L.hprfinal, 3)));
    for rmax = [60 150]
        in = r > 5 & r < rmax & abs(m) < 80;
        h = fminsearch(@(h) median(abs(m(in) - atand(h./r(in)))), depth - 1);
        fprintf('  lander %d, within %3d m (%4d clicks): %.1f m; median residual %+.1f deg at 16 m, %+.1f deg at %.1f m\n', ...
            landers(i), rmax, sum(in), h, median(m(in) - atand((depth - 1)./r(in))), ...
            median(m(in) - atand(h./r(in))), h);
    end
end
xlabel(ax, 'Range to the boat (m)');
exportgraphics(f, fullfile(outfolder, 'locate_residuals.png'), 'Resolution', 150);
fprintf('Saved %s\n', fullfile(outfolder, 'locate_residuals.png'));
