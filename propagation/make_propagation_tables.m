%MAKE_PROPAGATION_TABLES Build the ray traced propagation tables of the
%CTD casts taken at a lander array, for LOCALISEPORPOISES.
%
%   Every CastAway cast within MAXDIST of the array is ray traced with
%   ACTUP BELLHOP(M) (MAKE_PROPAGATION_TABLE) and saved as a struct
%   PROPAGATION in its own .mat file, <cast>_propagation.mat, in a
%   'propagation' folder beside the array file. All of them are also saved
%   together, as a struct array PROPAGATION in propagation_tables.mat, so
%   localiseporpoises(..., 'propagation', propagation) picks the cast
%   closest in time to each encounter.
%
%       load(fullfile(getlandersuperfolder('Denmark'), 'propagation', 'propagation_tables.mat'));
%       loctracks = localiseporpoises(landers, arrayfile, 'propagation', propagation);
%
%   Requires ACTUP in ~/MATLAB-Drive/MATLAB/ACTUP.
%
%   See also MAKE_PROPAGATION_TABLE, STRAIGHT_PROPAGATION, LOCALISEPORPOISES.

clear
here = fileparts(mfilename('fullpath'));
addpath(here);

%% Inputs
country    = 'Denmark';
deployment = 1;
maxdist    = 3000;      % casts within this distance of the array (m)
hdepth     = 17;        % hydrophone depth (m): the lander depth LOCALISEPORPOISES uses
overwrite  = true;      % trace a cast again even if its table is saved

%% The casts at the array
superfolder = fullfile(getenv('HOME'), 'Dropbox', 'SMRU_research', '2026-27_CUMBIAH', 'landers', country);
if exist('getlandersuperfolder', 'file')
    superfolder = getlandersuperfolder(country);
end
svpfolder = fullfile(superfolder, 'All_SVP_CastAway_Data');
arrayfile = fullfile(superfolder, sprintf('lander_array_locations_dep%d.mat', deployment));
outfolder = fullfile(superfolder, 'propagation');
if ~isfolder(outfolder), mkdir(outfolder); end

A = load(arrayfile);
site = mean(A.locstable.locationfine, 1);
if isfield(A, 'depth') && A.depth ~= hdepth
    warning('The array file gives a lander depth of %g m; the tables are for %g m.', A.depth, hdepth);
end
casts = load_site_svps(svpfolder, site);
casts = casts([casts.dist] <= maxdist);
fprintf('%d casts within %g m of the array\n', numel(casts), maxdist);

%% Ray trace each cast
clear propagation
for i = 1:numel(casts)
    [~, stem] = fileparts(casts(i).file);
    matfile = fullfile(outfolder, [stem '_propagation.mat']);
    if isfile(matfile) && ~overwrite
        S = load(matfile);
        P = S.propagation;
        fprintf('%s: loaded\n', stem);
    else
        t0 = tic;
        P = make_propagation_table(fullfile(svpfolder, casts(i).file), 'hdepth', hdepth);
        propagation = P; %#ok<NASGU>
        save(matfile, 'propagation');
        fprintf('%s: traced in %.0f s, c at the landers %.1f m/s, %.1f%% of the table in shadow\n', ...
            stem, toc(t0), P.soundspeed, 100*mean(P.shadow(:)));
    end
    props(i) = P; %#ok<SAGROW>
end
propagation = props;
save(fullfile(outfolder, 'propagation_tables.mat'), 'propagation');
fprintf('Saved %d tables to %s\n', numel(propagation), fullfile(outfolder, 'propagation_tables.mat'));

%% A synthetic autumn profile
% No cast was taken during deployment 1 (Oct 2024). In autumn the surface
% cools towards the temperature of the bottom water, which leaves the
% salinity step of the halocline: the June casts at the array had 9 PSU at
% the surface and 12.7 PSU at the seabed, about +4.5 m/s, at 10-14 m. This
% profile is upward refracting (the opposite of the September thermocline).
% It is NOT in propagation_tables.mat, so it is never picked by time.
syn.depth = (0:0.5:hdepth + 0.5)';
syn.c = 1470 + 4.5*min(max((syn.depth - 10)/4, 0), 1);
syn.time = NaT;
syn.file = 'synthetic_autumn_halocline';
syn.lat = site(1); syn.lon = site(2);
matfile = fullfile(outfolder, [syn.file '_propagation.mat']);
if ~isfile(matfile) || overwrite
    propagation = make_propagation_table(syn, 'hdepth', hdepth); %#ok<NASGU>
    save(matfile, 'propagation');
    fprintf('%s: traced\n', syn.file);
end
