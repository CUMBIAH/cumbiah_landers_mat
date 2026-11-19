%Compare the location results from two marked up datasets for lander 2 in
%Denmark.
%
% Two analysts marked out the boat calibration clicks for lander 2 in their
% own copy of the PAMGuard database, and the locations LOCATEPLATFORM gets
% from them disagree. This script first compares the marked clicks
% themselves, straight from the databases, and then locates the lander
% from each database in turn and plots the results side by side.
%
% Each run is a row of RUNS - a label, a database, the binary store that
% database was made from and the PAMGuard event type holding the
% calibration clicks. The two databases come from separate runs of the click
% detector, each with its own binary store, so the same click has a
% different UID in each and a database only reads correctly against its own
% binaries. GETLANDERPATHS knows only the original binary store, so the
% binary folder in DATA is swapped for each run.
%
% LOCATEPLATFORM reads only one event type, so every calibration line has to
% be marked with that type to be used.
%
% The localisation is slow so the results are kept in RESULTSFILE and only
% recalculated when the runs or the databases change or when RECALCULATE is
% true.
%
% See also LOCATE_PLATFORM, LOCATEPLATFORM, LOCATE_ARRAY.
clear
close all

country      = 'Denmark';
landernumber = 2;
deployment   = 1;
depth        = 17;

landerdir = '/Users/jdjm/Library/CloudStorage/Dropbox/SMRU_research/2026-27_CUMBIAH/landers/Denmark/lander2';

runs = struct( ...
    'label',     {'Annotated (Michael)', 'Original'}, ...
    'database',  {fullfile(landerdir, 'pamguard_michael', 'lander2_Denmark_database_annotated.sqlite3'), ...
                  fullfile(landerdir, 'pamguard', 'lander2_Denmark_database.sqlite3')}, ...
    'binaryfolder', {fullfile(landerdir, 'pamguard_michael', 'pamguard', 'PAMBinary'), ...
                     fullfile(landerdir, 'pamguard', 'PAMBinary')}, ...
    'eventtype', {'bc', 'bc'});

recalculate = false; % force the localisation to be run again

resultsfile = fullfile(landerdir, sprintf('compare_lander%d_dep%d.mat', landernumber, deployment));

nrun = numel(runs);

[startTime, ~, serialnumber] = getlanderdeploymentinfo(landernumber, deployment, country);
data = getlanderpaths(serialnumber, startTime);

%% Compare the marked clicks in the databases

%every event clicks on the calibration day, read straight from the database
%so no binary files are needed
calibday = [datenum(dateshift(startTime, 'start', 'day')) datenum(dateshift(startTime, 'end', 'day'))];
dbclicks = cell(1, nrun);
for i = 1:nrun
    dbclicks{i} = loaddbclicks(runs(i).database, calibday);

    fprintf('\n%s: %s\n', runs(i).label, runs(i).database);
    types = unique(dbclicks{i}.eventType);
    for k = 1:numel(types)
        intype = strcmp(dbclicks{i}.eventType, types{k});
        fprintf('  event type %-5s %3d events %7d clicks  %s to %s\n', types{k}, ...
            numel(unique(dbclicks{i}.eventId(intype))), sum(intype), ...
            datestr(min(dbclicks{i}.time(intype)), 'HH:MM:SS'), ...
            datestr(max(dbclicks{i}.time(intype)), 'HH:MM:SS'));
    end
end

%the clicks that are actually used, shared between each pair of runs. The
%UIDs differ between the binary stores so clicks are matched on their time,
%to the millisecond.
fprintf('\nClicks shared between the runs (by time):\n');
pairs = nchoosek(1:nrun, 2);
for k = 1:size(pairs, 1)
    a = pairs(k,1);
    b = pairs(k,2);
    ta = usedtimes(dbclicks{a}, runs(a).eventtype);
    tb = usedtimes(dbclicks{b}, runs(b).eventtype);
    nboth = numel(intersect(ta, tb));
    fprintf('  %s (%d) vs %s (%d): %d in both, %d only in %s, %d only in %s\n', ...
        runs(a).label, numel(ta), runs(b).label, numel(tb), nboth, ...
        numel(ta) - nboth, runs(a).label, numel(tb) - nboth, runs(b).label);
end

cols = getdefaultcols();

%when each database has calibration clicks marked - gaps here are boat
%lines that one analyst used and the other did not
figure(1)
clf
hold on
h = gobjects(1, nrun);
for i = 1:nrun
    used = strcmp(dbclicks{i}.eventType, runs(i).eventtype);
    t = datetime(dbclicks{i}.time(used), 'ConvertFrom', 'datenum');
    h(i) = plot(t, i*ones(size(t)), '.', 'Color', cols(i,:), 'MarkerSize', 8);

    %clicks in the database that this run does not use
    t = datetime(dbclicks{i}.time(~used), 'ConvertFrom', 'datenum');
    plot(t, i*ones(size(t)) - 0.2, '.', 'Color', [0.6 0.6 0.6], 'MarkerSize', 4);
end
hold off
yticks(1:nrun)
yticklabels(arrayfun(@(r) sprintf('%s (%s)', r.label, r.eventtype), runs, 'UniformOutput', false))
ylim([0.5 nrun+0.5])
xlabel('Time')
title({'Marked calibration clicks', 'grey: events of other types, not used'})
set(gca, 'FontSize', 12)

%% Locate the lander from each database

%a database edited since the results were saved (events re-marked, say)
%means the results are out of date too
dbmodified = arrayfun(@(r) dir(r.database).datenum, runs);

dorecalc = recalculate || ~isfile(resultsfile);
if ~dorecalc
    cached = load(resultsfile);
    dorecalc = ~isfield(cached, 'dbmodified') || ~isequal(cached.runs, runs) || ...
        ~isequal(cached.dbmodified, dbmodified) || cached.depth ~= depth;
end

if dorecalc
    %the chi2 surfaces are GBs so only what the comparison needs is kept
    keep = {'location', 'locationfine', 'hprfinal', 'headingoffset', 'headingstd', ...
        'rtctimeoffset', 'rtcoffset', 'chi2offsets', 'chi2', 'chi2fine', 'clickbearings', ...
        'clkangdiff', 'srcclklocations', 'droplocation', 'sqlitedB'};
    locs = struct();
    for i = 1:nrun
        disp(['Locating lander ' num2str(landernumber) ' from ' runs(i).label]);
        rundata = data;
        rundata.binaryfolder = runs(i).binaryfolder;
        results = locateplatform(rundata, 'depth', depth, 'database', runs(i).database, ...
            'eventtype', runs(i).eventtype, 'gridlims', [-50 50], 'gridcenter', data.droplocation);
        for k = 1:numel(keep)
            locs(i).(keep{k}) = results.(keep{k});
        end
    end
    clear results
    save(resultsfile, 'locs', 'runs', 'depth', 'dbmodified');
else
    locs = cached.locs;
    disp(['Loaded lander locations from ' resultsfile]);
end

%% Summary

dropgpsloc = data.droplocation;
summary = table('Size', [nrun 9], ...
    'VariableTypes', {'string', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double'}, ...
    'VariableNames', {'run', 'nbearings', 'rtcoffset', 'lat', 'lon', 'dropdist', 'heading', 'pitch', 'roll'});
for i = 1:nrun
    summary.run(i)       = runs(i).label;
    summary.nbearings(i) = size(locs(i).clickbearings, 1);
    summary.rtcoffset(i) = locs(i).rtctimeoffset;
    summary.lat(i)       = locs(i).locationfine(1);
    summary.lon(i)       = locs(i).locationfine(2);
    summary.dropdist(i)  = latLong2meters(dropgpsloc(1), dropgpsloc(2), ...
        locs(i).locationfine(1), locs(i).locationfine(2));
    summary.heading(i)   = locs(i).hprfinal(1);
    summary.pitch(i)     = locs(i).hprfinal(2);
    summary.roll(i)      = locs(i).hprfinal(3);
end
format long g
disp(summary)
format short

for k = 1:size(pairs, 1)
    a = pairs(k,1);
    b = pairs(k,2);
    d = latLong2meters(locs(a).locationfine(1), locs(a).locationfine(2), ...
        locs(b).locationfine(1), locs(b).locationfine(2));
    dc = latLong2meters(locs(a).location(1), locs(a).location(2), ...
        locs(b).location(1), locs(b).location(2));
    fprintf('%s to %s: %.1f m apart (coarse %.1f m), heading differs by %.1f degrees\n', ...
        runs(a).label, runs(b).label, d, dc, angdiffd(locs(a).hprfinal(1), locs(b).hprfinal(1)));
end

%% Plot

%the positions in metres east and north of the drop position
figure(2)
clf
hold on
h = gobjects(0);
labels = {};
for i = 1:nrun
    src = locs(i).srcclklocations;
    [~, sx, sy] = latLong2meters(dropgpsloc(1), dropgpsloc(2), src(:,2), src(:,3));
    h(end+1) = plot(sx, sy, '.', 'Color', [cols(i,:) 0.3], 'MarkerSize', 4);
    labels{end+1} = sprintf('%s boat positions', runs(i).label);
end
for i = 1:nrun
    [~, cx, cy] = latLong2meters(dropgpsloc(1), dropgpsloc(2), locs(i).location(1), locs(i).location(2));
    [~, fx, fy] = latLong2meters(dropgpsloc(1), dropgpsloc(2), locs(i).locationfine(1), locs(i).locationfine(2));
    plot([cx fx], [cy fy], ':', 'Color', cols(i,:), 'LineWidth', 1.5);
    plot(cx, cy, 's', 'MarkerSize', 9, 'MarkerEdgeColor', cols(i,:), 'LineWidth', 2);
    h(end+1) = plot(fx, fy, 'o', 'MarkerSize', 11, 'MarkerFaceColor', cols(i,:), 'MarkerEdgeColor', 'k');
    labels{end+1} = sprintf('%s fine (%.1f m from drop)', runs(i).label, summary.dropdist(i));
end
h(end+1) = plot(0, 0, 'kx', 'MarkerSize', 14, 'LineWidth', 2);
labels{end+1} = 'Drop';
hold off
axis equal
legend(h, labels, 'Location', 'northeastoutside')
xlabel('Eastings (m)')
ylabel('Northings (m)')
title({sprintf('Lander %d, deployment %d', landernumber, deployment), 'squares: coarse location'})
set(gca, 'FontSize', 12)

%zoom in on the landers
figure(3)
clf
ax = copyobj([findobj(2, 'Type', 'legend') findobj(2, 'Type', 'axes')], 3);
ax = ax(2);
allx = []; ally = [];
for i = 1:nrun
    [~, fx, fy] = latLong2meters(dropgpsloc(1), dropgpsloc(2), ...
        [locs(i).location(1) locs(i).locationfine(1)], [locs(i).location(2) locs(i).locationfine(2)]);
    allx = [allx fx]; ally = [ally fy]; %#ok<AGROW>
end
pad = 10;
xlim(ax, [min([allx 0])-pad max([allx 0])+pad])
ylim(ax, [min([ally 0])-pad max([ally 0])+pad])

%chi2 against the SoundTrap clock offset
figure(4)
clf
hold on
for i = 1:nrun
    plot(locs(i).rtcoffset, locs(i).chi2offsets, '.-', 'Color', cols(i,:), 'MarkerSize', 12);
end
hold off
legend(arrayfun(@(i) sprintf('%s (best %gs)', runs(i).label, locs(i).rtctimeoffset), 1:nrun, ...
    'UniformOutput', false))
xlabel('Time offset (seconds)')
ylabel('chi2')
set(gca, 'FontSize', 12)

%the difference between the click bearings and the bearings to the boat -
%the heading. Lines that disagree between the runs stand out here.
figure(5)
clf
hold on
h = gobjects(1, nrun);
for i = 1:nrun
    h(i) = scatter(datetime(locs(i).clickbearings(:,1), 'ConvertFrom', 'datenum'), locs(i).clkangdiff, ...
        6, cols(i,:), 'filled', 'MarkerFaceAlpha', 0.4);
    yline(locs(i).headingoffset, 'Color', cols(i,:), 'LineWidth', 2);
end
hold off
legend(h, arrayfun(@(i) sprintf('%s %.1f +/- %.1f degrees', runs(i).label, ...
    locs(i).headingoffset, locs(i).headingstd), 1:nrun, 'UniformOutput', false))
ylabel('Bearing difference (degrees)')
xlabel('Time')
set(gca, 'FontSize', 12)

%the click bearings of each run over time
figure(6)
clf
for i = 1:nrun
    subplot(nrun, 1, i)
    scatter(datetime(locs(i).clickbearings(:,1), 'ConvertFrom', 'datenum'), ...
        locs(i).clickbearings(:,2), 6, cols(i,:), 'filled');
    ylabel('Bearing (degrees)')
    title(runs(i).label)
    ylim([-180 180])
end
xlabel('Time')

% ------------------------------------------------------------------------
function clicks = loaddbclicks(sqlitedb, timelims)
%LOADDBCLICKS Event clicks between TIMELIMS (datenums) straight from a database.
%   CLICKS is a table with the click UID, time (datenum), event Id and the
%   trimmed event type.

conn = sqlite(sqlitedb, 'readonly');
c = fetch(conn, ['select c.UID, c.UTC, e.Id, e.eventType from Click_Detector_OfflineClicks c ' ...
    'join Click_Detector_OfflineEvents e on c.parentID = e.Id']);
close(conn)

clicks = table();
clicks.uid       = double(c.UID);
clicks.time      = datenum(string(c.UTC), 'yyyy-mm-dd HH:MM:SS.FFF');
clicks.eventId   = double(c.Id);
clicks.eventType = strtrim(cellstr(string(c.eventType)));

clicks = clicks(clicks.time >= timelims(1) & clicks.time <= timelims(2), :);
clicks = sortrows(clicks, 'time');

end

% ------------------------------------------------------------------------
function t = usedtimes(clicks, eventtype)
%USEDTIMES Times of the clicks of one event type, in integer milliseconds.

t = unique(round(clicks.time(strcmp(clicks.eventType, eventtype))*86400e3));

end
