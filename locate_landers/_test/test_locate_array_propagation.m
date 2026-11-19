%% Test: locate the landers with straight lines and with ray traced propagation
%
% Locates every lander of the array from the boat calibration clicks with
% LOCATEPLATFORM (every click, as LOCATE_ARRAY, with the same lander 2
% database) once with straight lines and once with each propagation table,
% whose ray traced slants replace the straight line slants in the fine
% search ('propagation'). The tables are the CTD casts at the array
% (June and September 2025) and a synthetic autumn profile (the halocline
% only, upward refracting) - propagation/make_propagation_tables.m.
%
% For each model and lander it records the position, heading, pitch, roll
% and the chi2 of the fine search, and plots the slant residual (measured
% minus the model's slant) against range. The model with the lowest chi2
% fits the boat clicks best, which is a guide to the water on the day of
% the calibration. Nothing is written to the array file.
clear
close all

country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];
depth      = 17;
lander2db  = '/Users/jdjm/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander2/pamguard_michael/lander2_Denmark_database_annotated.sqlite3';
lander2bin = '/Users/jdjm/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander2/pamguard_michael/pamguard/PAMBinary';
tables = {'CC2043006_20250625_131201', 'CC2043006_20250625_141044', 'CC2043006_20250912_092555', ...
    'synthetic_autumn_halocline'};

%% Paths
here = fileparts(mfilename('fullpath'));
folders = strsplit(genpath(fileparts(fileparts(here))), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}) & ~contains(folders, [filesep '.']));
addpath(strjoin(folders, pathsep));

superfolder = getlandersuperfolder(country);
outfolder = fullfile(superfolder, 'propagation', 'lander_location');
if ~isfolder(outfolder), mkdir(outfolder); end

% the models: straight lines, then each table
models = struct('name', 'straight line', 'prop', []);
for t = 1:numel(tables)
    S = load(fullfile(superfolder, 'propagation', [tables{t} '_propagation.mat']));
    label = tables{t};
    if ~isnat(S.propagation.time)
        label = char(S.propagation.time, 'dd MMM yyyy HH:mm');
    end
    models(end+1) = struct('name', ['ray traced, ' label], 'prop', S.propagation); %#ok<SAGROW>
end

%% Locate, one model at a time (each is saved, so a run can be resumed)
for m = 1:numel(models)
    mfile = fullfile(outfolder, sprintf('locate_propagation_model%d.mat', m));
    if isfile(mfile)
        continue
    end
    clear F
    for i = 1:numel(landers)
        [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
        data = getlanderpaths(serialnumber, startTime);
        if landers(i) == 2 && ~isempty(lander2db)
            data.sqlitedB = lander2db;
            data.binaryfolder = lander2bin;
        end
        t0 = tic;
        res = locateplatform(data, 'depth', depth, 'gridlims', [-40 40], ...
            'gridcenter', data.droplocation, 'propagation', models(m).prop);
        fprintf('%s, lander %d: %.0f s\n', models(m).name, landers(i), toc(t0));
        F(i) = struct('lander', landers(i), 'locationfine', res.locationfine, 'hprfinal', res.hprfinal, ...
            'chi2fine', res.chi2fine, 'headingstd', res.headingstd, 'clkgeobearings', res.clkgeobearings, ...
            'srcclklocations', res.srcclklocations, 'validclk', res.validclk); %#ok<SAGROW>
    end
    model = models(m); %#ok<NASGU>
    save(mfile, 'F', 'model');
end

%% Collect
for m = 1:numel(models)
    S = load(fullfile(outfolder, sprintf('locate_propagation_model%d.mat', m)));
    fits{m} = S.F; %#ok<SAGROW>
end
ref = fits{1};
fprintf('\n%-38s %6s %18s %8s %8s %8s %8s\n', 'model', 'lander', 'hpr', 'move (m)', 'chi2', 'L1-L2', 'L1-L3');
summary = table();
for m = 1:numel(models)
    F = fits{m};
    d12 = latLong2meters(F(1).locationfine(1), F(1).locationfine(2), F(2).locationfine(1), F(2).locationfine(2));
    d13 = latLong2meters(F(1).locationfine(1), F(1).locationfine(2), F(3).locationfine(1), F(3).locationfine(2));
    d23 = latLong2meters(F(2).locationfine(1), F(2).locationfine(2), F(3).locationfine(1), F(3).locationfine(2));
    for i = 1:numel(landers)
        mv = latLong2meters(ref(i).locationfine(1), ref(i).locationfine(2), F(i).locationfine(1), F(i).locationfine(2));
        fprintf('%-38s %6d %18s %8.1f %8.3f %8.1f %8.1f\n', models(m).name, landers(i), mat2str(F(i).hprfinal, 3), ...
            mv, F(i).chi2fine, d12, d13);
        summary = [summary; table(string(models(m).name), landers(i), F(i).hprfinal, mv, F(i).chi2fine, ...
            [d12 d13 d23], 'VariableNames', {'model', 'lander', 'hpr', 'move', 'chi2', 'spacing'})]; %#ok<AGROW>
    end
end
save(fullfile(outfolder, 'locate_propagation_summary.mat'), 'summary', 'models');

%% Slant residuals against range for each model
cols = lines(numel(models));
f = figure('Position', [50 50 1400 360*numel(landers)], 'Color', 'w');
tl = tiledlayout(numel(landers), 1, 'TileSpacing', 'compact');
for i = 1:numel(landers)
    ax = nexttile(tl); hold(ax, 'on');
    h = gobjects(1, numel(models));
    for m = 1:numel(models)
        F = fits{m}(i);
        src = F.srcclklocations;                     % datenum lat lon depth difference
        r = nan(size(src, 1), 1);
        for k = find(~any(isnan(src(:,2:3)), 2))'
            r(k) = latLong2meters(F.locationfine(1), F.locationfine(2), src(k,2), src(k,3));
        end
        if isempty(models(m).prop)
            model = atand(src(:,4)./r);
        else
            P = models(m).prop;
            G = griddedInterpolant({P.ranges(:), P.depths(:)}, P.slant, 'linear', 'nearest');
            model = G(r, P.hdepth - src(:,4));
        end
        meas = rad2deg(rotate_bearings(F.clkgeobearings, F.hprfinal));
        resid = meas(:,2) - model;
        edges = [0:10:100, 125:25:max(r) + 25];
        bin = discretize(r, edges);
        g = ~isnan(bin) & ~isnan(resid);
        med = accumarray(bin(g), resid(g), [numel(edges)-1 1], @median, NaN);
        h(m) = plot(ax, (edges(1:end-1) + edges(2:end))/2, med, '-', 'Color', cols(m,:), 'LineWidth', 2);
    end
    yline(ax, 0, 'k');
    set(ax, 'XScale', 'log'); xlim(ax, [5 1500]); ylim(ax, [-8 8]); grid(ax, 'on'); box(ax, 'on');
    ylabel(ax, 'Measured - model slant (deg)');
    title(ax, sprintf('Lander %d: median residual, each model refitted', landers(i)));
    if i == 1
        legend(ax, h, {models.name}, 'Location', 'southeast');
    end
end
xlabel(ax, 'Range to the boat (m)');
exportgraphics(f, fullfile(outfolder, 'locate_propagation_residuals.png'), 'Resolution', 150);
fprintf('Saved %s\n', fullfile(outfolder, 'locate_propagation_residuals.png'));
