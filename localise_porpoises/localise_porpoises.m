%% Localise the porpoise tracks of a CUMBIAH lander array
%
% Pick a country, a deployment and the landers of an array, let
% GETLANDERDEPLOYMENTINFO and GETLANDERPATHS find the data and hand the
% records, with the array file of LOCATE_ARRAY, to LOCALISEPORPOISES. Run
% it after locate_array.m (where the landers are and how they lie) and
% after cumbiah_multitrack.m has been run for each lander (the bearing
% tracks in each lander's ..._porpoise.sqlite3 database).
%
% LOCALISEPORPOISES does the work: it matches the tracks between the
% landers, lines up their clocks with a comb filter and localises the
% matched tracks with the particle filter - see its help for how. Nothing
% is written to the databases.
%
% Output, in OUTFOLDER, where <name> is e.g. landers123_dep1:
%   <name>_loctracks.mat  - the localised tracks, with the clock offsets and
%                           associations of every encounter
%   <name>_PAnnnn_loctracks.png/.fig - every track of an encounter over the
%                           seabed, coloured by time, with the landers
%   <name>_PAnnnn_association.png - the tracks of the encounter on each
%                           lander, coloured by association
%   <name>_clock.png      - the clock of each lander through the deployment
%
% Needs the CUMBIAH library, soundnet, PAMGUARD and the CIBBRiNA
% soundtrap_4c code on the MATLAB path.
clear
close all

%% Inputs
% Lander and deployment numbers are per country - for Denmark, landers 1-9
% and deployments 1 = Oct 24, 2 = Feb 25, 3 = June 25. The first lander is
% the reference: every time is on its clock.
country    = 'Denmark';
deployment = 1;
landers    = [1 2 3];

% the positions and orientations of the landers, saved by locate_array.m
arrayfile = fullfile(getlandersuperfolder(country), ...
    sprintf('lander_array_locations_dep%d.mat', deployment));

encounters = [];        % encounters to localise, e.g. 3:5 for PA1003-PA1005; [] = all
tlims = [];             % [start end] datetime of the tracks used; [] = the whole deployment
localise = true;        % false = match the tracks and stop: quick, to check the clocks and matching
outfolder = '';         % results folder; '' = <lander super folder>/localisation

% particle filter (porpoise). 10 runs of 2000 particles is the most careful
% but takes about 1 s for every click, i.e. many hours for a deployment. 5
% runs of 1000 is about five times quicker.
nruns = 5;              % the number of runs for the particle filter
particles = 1000;       % particles in each run

%% Paths
% the particle filter and time delay code are not on the startup path
root = fullfile(matlabdrive, 'MATLAB');
folders = strsplit(genpath(fullfile(root, 'localisation')), pathsep);
[~, names] = cellfun(@fileparts, folders, 'UniformOutput', false);
folders = folders(~ismember(names, {'_old', '_test', '_tests', ''}));
addpath(strjoin([folders, {fullfile(root, 'sim_sounds', 'sim_utils')}], pathsep));

%% The landers
% one deployment record for each lander of the array
data = cell(1, numel(landers));
for i = 1:numel(landers)
    [startTime, ~, serialnumber] = getlanderdeploymentinfo(landers(i), deployment, country);
    data{i} = getlanderpaths(serialnumber, startTime);
end

%% Match, time align and localise
% every other setting (encounters, clocks, matching, start locations,
% plots) is a name-value option of LOCALISEPORPOISES
[loctracks, info] = localiseporpoises(data, arrayfile, 'encounters', encounters, 'tlims', tlims, ...
    'localise', localise, 'outfolder', outfolder, 'nruns', nruns, 'particles', particles);

%% Plot every track of the run
% the encounter figures are saved as the function goes; this one is all of
% the tracks together, coloured by time within their encounter
if ~isempty(loctracks)
    figure('Position', [0, 0, 1100, 700]);
    xy = [loctracks.xh];
    lims = min(500, max(100, 50*ceil(prctile(max(abs(xy(1:2,:))), 95)/50)));
    plot_loctrack_landers(loctracks, info.settings.landerxyz, info.meshdata, ...
        'landernumbers', info.settings.landers, 'lims', lims, 'showtitle', false);
    zlim([min(info.meshdata.z(:)) - 2, 2])
    view([30, 45])
    title(sprintf('%s landers %s, deployment %d: %d tracks of %d encounters', country, ...
        num2str(landers), deployment, numel(loctracks), numel(unique([loctracks.encounter]))));
    set(gca, 'FontSize', 14);
end
