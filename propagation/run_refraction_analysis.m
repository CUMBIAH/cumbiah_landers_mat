%RUN_REFRACTION_ANALYSIS How refraction biases the slant angle a seabed
%lander measures, and so the depth the localiser gives a porpoise.
%
%   The Danish lander array (deployment 1) sits in ~17 m of water south of
%   Falster. The localiser (LOCALISEPORPOISES) crosses straight line
%   bearings, so a click's slant angle maps straight to a depth. This
%   script ray traces real CastAway sound speed profiles from the site with
%   the ACTUP BELLHOP(M) ray tracer and compares the slant angle a click
%   really arrives from with the straight line slant, for porpoises at
%   ranges of 5-250 m and every depth in the water column. It also looks at
%   the -10 deg slant cut-off ('minslant') the localiser applies.
%
%   Plots are saved to PLOTFOLDER. Requires ACTUP in ~/MATLAB-Drive/MATLAB/ACTUP.
%
%   See also SLANT_REFRACTION_BIAS, ACTUP_TRACE_RAYS, LOAD_SITE_SVPS.

clear; close all;
here = fileparts(mfilename('fullpath'));
addpath(here);

% ---- settings -----------------------------------------------------------
denmark   = fullfile(getenv('HOME'), 'Dropbox', 'SMRU_research', '2026-27_CUMBIAH', 'landers', 'Denmark');
svpfolder = fullfile(denmark, 'All_SVP_CastAway_Data');
arrayfile = fullfile(denmark, 'lander_array_locations_dep1.mat');
plotfolder = fullfile(denmark, 'localisation', 'refraction_analysis');

seabed  = 17.2;      % water depth at the landers from the bathymetry (m)
hdepth  = 16.7;      % lander hydrophone depth: assumed 0.5 m above the seabed (m)
ranges  = 5:5:250;   % horizontal range of the porpoise (m)
depths  = 0.5:0.5:16.5; % porpoise depth (m)
angles  = -75:0.02:75;  % ray fan (deg, + down)
sitekm  = 3;         % casts within this distance of the array are "site" casts (km)
minslant = -10;      % the localiser's slant cut-off (deg)

if ~isfolder(plotfolder), mkdir(plotfolder); end

A = load(arrayfile);
site = mean(A.locstable.locationfine, 1);
casts = load_site_svps(svpfolder, site, 'seabed', seabed);
issite = [casts.dist] < sitekm*1000;
fprintf('%d casts, %d within %g km of the array:\n', numel(casts), sum(issite), sitekm);
for c = casts(issite)
    fprintf('  %s  %.0f m away\n', c.file, c.dist);
end

% ---- ray trace every cast -----------------------------------------------
% the site casts on the full grid, the rest (other stations, cut to the
% top 17 m) on a coarser grid as a guide to how variable the Baltic is
for i = 1:numel(casts)
    t0 = tic;
    if issite(i)
        casts(i).B = slant_refraction_bias(casts(i).zgrid, casts(i).cgrid, hdepth, ranges, depths, 'angles', angles);
    else
        casts(i).B = slant_refraction_bias(casts(i).zgrid, casts(i).cgrid, hdepth, [50 100 150 200], depths, 'angles', -75:0.05:75);
    end
    fprintf('%s traced (%.0f s)\n', casts(i).file, toc(t0));
end
% isovelocity check: the ray tracer should give zero bias
iso = slant_refraction_bias(casts(1).zgrid, 1480*ones(size(casts(1).zgrid)), hdepth, ranges, depths, 'angles', angles);
fprintf('Isovelocity check: max |slant bias| %.3f deg, max |depth error| %.3f m\n', ...
    max(abs(iso.D.bias(:)), [], 'omitnan'), max(abs(iso.D.deptherr(:)), [], 'omitnan'));

S = casts(issite);
labels = arrayfun(@(c) string(datetime(c.time, 'Format', 'dd MMM yyyy HH:mm')), S);
save(fullfile(plotfolder, 'refraction_analysis.mat'), 'S', 'iso', 'seabed', 'hdepth', 'ranges', 'depths', 'minslant', '-v7.3');

cmapdiv = interp1([0 0.5 1], [0.13 0.40 0.75; 0.97 0.97 0.97; 0.80 0.25 0.15], linspace(0, 1, 256));

% ---- 1. sound speed profiles --------------------------------------------
f = figure('Position', [100 100 900 500], 'Color', 'w');
tiledlayout(1, 2, 'TileSpacing', 'compact');
nexttile; hold on;
for c = casts(~issite)
    plot(c.c, c.depth, 'Color', [0.8 0.8 0.8]);
end
co = lines(numel(S));
for i = 1:numel(S)
    hl(i) = plot(S(i).c, S(i).depth, 'Color', co(i,:), 'LineWidth', 2); %#ok<SAGROW>
end
yline(hdepth, 'k--', 'hydrophone'); yline(seabed, 'k-', 'seabed');
set(gca, 'YDir', 'reverse'); ylim([0 25]); grid on; box on;
xlabel('Sound speed (m/s)'); ylabel('Depth (m)');
legend(hl, labels, 'Location', 'southwest');
title('CastAway casts (site in colour, other stations grey)');
nexttile; hold on;
for i = 1:numel(S)
    plot(S(i).temp, S(i).depth, '-', 'Color', co(i,:), 'LineWidth', 1.5);
end
set(gca, 'YDir', 'reverse'); ylim([0 seabed]); grid on; box on;
xlabel('Temperature (\circC)'); ylabel('Depth (m)');
yyaxis right; hold on;
for i = 1:numel(S)
    plot(S(i).sal, S(i).depth, ':', 'Color', co(i,:), 'LineWidth', 1.5);
end
set(gca, 'YDir', 'reverse'); ylim([0 seabed]); ylabel('Depth (m)');
title('Site casts: temperature (solid), salinity (dotted, PSU)');
xlim auto
exportgraphics(f, fullfile(plotfolder, 'svp_profiles.png'), 'Resolution', 150);

% ---- 2. ray fans --------------------------------------------------------
f = figure('Position', [100 100 1100 330*numel(S)], 'Color', 'w');
tiledlayout(numel(S), 1, 'TileSpacing', 'compact');
for i = 1:numel(S)
    nexttile; hold on;
    R = S(i).B.ray;
    for k = 1:numel(R)
        a = R(k).angle;
        if a > 0 || mod(round(a/0.02), 25) ~= 0 || a < -20, continue; end
        d = R(k).nbnc == 0;
        plot(R(k).r(d), R(k).z(d), 'Color', [0.1 0.3 0.7 0.6]);
    end
    yline(seabed, 'k', 'LineWidth', 1.5);
    plot(0, hdepth, 'r^', 'MarkerFaceColor', 'r');
    set(gca, 'YDir', 'reverse'); xlim([0 250]); ylim([0 seabed]); box on;
    ylabel('Depth (m)');
    title(sprintf('Direct ray paths from the lander, %s (every 0.5\\circ, 0 to 20\\circ up)', labels(i)));
end
xlabel('Horizontal range (m)');
exportgraphics(f, fullfile(plotfolder, 'ray_fans.png'), 'Resolution', 150);

% ---- 3. slant bias and depth error maps ---------------------------------
f = figure('Position', [100 100 1100 330*numel(S)], 'Color', 'w');
tiledlayout(numel(S), 2, 'TileSpacing', 'compact');
for i = 1:numel(S)
    P = S(i).B.D;
    nexttile;
    imagesc(ranges, depths, P.bias', 'AlphaData', ~isnan(P.bias'));
    colormap(gca, cmapdiv); clim([-4 4]); cb = colorbar; cb.Label.String = 'slant bias (\circ)';
    hold on; contour(ranges, depths, P.bias', [0.5 1 2 4], 'k', 'ShowText', 'on');
    ylabel('Porpoise depth (m)'); title(sprintf('Slant bias (true - straight line), %s', labels(i)));
    nexttile;
    imagesc(ranges, depths, P.deptherr', 'AlphaData', ~isnan(P.deptherr'));
    colormap(gca, cmapdiv); clim([-15 15]); cb = colorbar; cb.Label.String = 'depth error (m)';
    hold on; contour(ranges, depths, P.deptherr', [-10 -5 -2 -1], 'k', 'ShowText', 'on');
    title('Straight line depth - true depth (- = too shallow)');
end
for ax = findall(f, 'Type', 'axes')'
    set(ax, 'YDir', 'reverse'); ax.XLabel.String = 'Horizontal range (m)';
end
exportgraphics(f, fullfile(plotfolder, 'slant_bias_maps.png'), 'Resolution', 150);

% ---- 4. slant vs range for a few porpoise depths, with echoes -----------
showz = [1 5 10 14];
f = figure('Position', [100 100 1100 380*numel(S)], 'Color', 'w');
tiledlayout(numel(S), 1, 'TileSpacing', 'compact');
for i = 1:numel(S)
    nexttile; hold on;
    co = lines(numel(showz)); h = gobjects(0); lab = strings(0);
    for j = 1:numel(showz)
        k = find(abs(depths - showz(j)) < 1e-6);
        h(end+1) = plot(ranges, S(i).B.D.slant(:,k), '-', 'Color', co(j,:), 'LineWidth', 2); %#ok<SAGROW>
        lab(end+1) = sprintf('%g m deep', showz(j)); %#ok<SAGROW>
        plot(ranges, S(i).B.D.geom(:,k), '--', 'Color', co(j,:));
        plot(ranges, S(i).B.B.slant(:,k), '-.', 'Color', co(j,:), 'LineWidth', 1);
    end
    yline(minslant, 'r', sprintf('minslant %g\\circ', minslant), 'LineWidth', 1.5);
    yline(0, 'k:');
    h(end+1) = plot(nan, nan, 'k-', 'LineWidth', 2); lab(end+1) = 'direct, ray traced';
    h(end+1) = plot(nan, nan, 'k--'); lab(end+1) = 'direct, straight line';
    h(end+1) = plot(nan, nan, 'k-.'); lab(end+1) = 'seabed echo, ray traced';
    legend(h, lab, 'Location', 'eastoutside');
    ylim([-25 25]); xlim([0 250]); grid on; box on;
    ylabel('Slant at the lander (\circ, + up)');
    title(labels(i));
end
xlabel('Horizontal range (m)');
exportgraphics(f, fullfile(plotfolder, 'slant_vs_range.png'), 'Resolution', 150);

% ---- 5. the -10 deg cut-off ---------------------------------------------
f = figure('Position', [100 100 1100 420], 'Color', 'w');
tiledlayout(1, 2, 'TileSpacing', 'compact');
nexttile;
% the range beyond which a seabed echo arrives above minslant and so is kept
Pb = S(end).B.B; Pg = S(1).B.B;
pass = nan(numel(depths), 2);
for k = 1:numel(depths)
    j = find(Pg.slant(:,k) > minslant, 1); if ~isempty(j), pass(k,1) = ranges(j); end
    j = find(Pb.slant(:,k) > minslant, 1); if ~isempty(j), pass(k,2) = ranges(j); end
end
geompass = (2*seabed - depths - hdepth)/tand(-minslant);
plot(geompass, depths, 'k--', pass(:,1), depths, '-', pass(:,2), depths, '-', 'LineWidth', 2);
set(gca, 'YDir', 'reverse'); grid on; box on; xlim([0 120]);
xlabel('Range beyond which the seabed echo passes the cut (m)'); ylabel('Porpoise depth (m)');
legend('straight line', labels(1), labels(end), 'Location', 'southeast');
title(sprintf('Seabed echoes arrive above %g\\circ', minslant));
nexttile; hold on;
lo = nan(numel(S), numel(ranges));
for i = 1:numel(S)
    lo(i,:) = min(S(i).B.D.slant, [], 2, 'omitnan');
end
plot(ranges, lo, 'LineWidth', 2);
yline(minslant, 'r', 'LineWidth', 1.5);
grid on; box on; xlim([0 250]); ylim([-12 2]);
xlabel('Horizontal range (m)'); ylabel('Lowest direct path slant (\circ)');
legend(labels, 'Location', 'southeast');
title('Lowest slant a direct click can arrive from');
exportgraphics(f, fullfile(plotfolder, 'minslant_cutoff.png'), 'Resolution', 150);

% ---- 6. every cast: depth error at 100 and 150 m ------------------------
f = figure('Position', [100 100 1100 420], 'Color', 'w');
hold on;
rr = [100 150];
mk = {'o', 's'};
for j = 1:numel(rr)
    e = nan(numel(casts), 1); g = e;
    for i = 1:numel(casts)
        k = find(casts(i).B.ranges == rr(j));
        e(i) = median(casts(i).B.D.deptherr(k, depths <= 10), 'omitnan');
        g(i) = range(casts(i).cgrid);
    end
    scatter(g(~issite), e(~issite), 50, [0.6 0.6 0.6], mk{j});
    scatter(g(issite), e(issite), 80, 'r', mk{j}, 'filled');
end
xlabel('Sound speed range in the top 17 m (m/s)');
ylabel('Median depth error, porpoise 0-10 m deep (m)');
legend('other stations, 100 m', 'site, 100 m', 'other stations, 150 m', 'site, 150 m', 'Location', 'southwest');
grid on; box on;
title('Depth error of a straight line localiser for every CastAway cast');
exportgraphics(f, fullfile(plotfolder, 'all_casts_depth_error.png'), 'Resolution', 150);

% ---- summary numbers ----------------------------------------------------
fprintf('\nSummary (direct path):\n');
for i = 1:numel(S)
    P = S(i).B.D;
    for r = [50 100 150 200]
        k = ranges == r;
        fprintf('  %s  range %3d m: slant bias %5.2f to %5.2f deg, depth error %6.1f to %5.1f m, shadow %d of %d depths\n', ...
            labels(i), r, min(P.bias(k,:)), max(P.bias(k,:)), min(P.deptherr(k,:)), max(P.deptherr(k,:)), ...
            sum(isnan(P.slant(k,:))), numel(depths));
    end
    fprintf('    mean sound speed %.1f m/s\n', mean(S(i).cgrid));
end
fprintf('Plots saved to %s\n', plotfolder);
