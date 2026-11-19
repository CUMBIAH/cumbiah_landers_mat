function [htrack, hlanders, hbearings, hnow, hout, hcircle] = plot_loctrack_frame(loctracks, landerxyz, meshdata, clicks, time, varargin)
%PLOT_LOCTRACK_FRAME Plots one frame of a movie of porpoise tracks around a lander array.
%
%   PLOT_LOCTRACK_FRAME(LOCTRACKS, LANDERXYZ, MESHDATA, CLICKS, TIME) plots,
%   in the current axes, the landers and seabed (PLOT_LANDER_ARRAY), every
%   localised track up to TIME coloured by time, the latest position of
%   each track still running, and the true bearings of the clicks each
%   lander heard in the BEARINGWINDOW seconds up to TIME, drawn out from the
%   lander in the colour of the lander. It is the lander version of
%   PLOTBYCATCHLOCTRACKSFRAME: all the animals on one plot. Call it once
%   for a plan view and once more, with view([0 0]), for a side view.
%
%   LOCTRACKS is a struct array of localised tracks (xh, loctracktimes,
%   datestart), LANDERXYZ the [n x 3] positions of the landers [east north
%   up] (m) and MESHDATA the seabed, as returned by LOCALISEPORPOISES.
%   CLICKS has one element per lander, in the order of LANDERXYZ, with t,
%   the time of each click (datenum, ON THE REFERENCE LANDER'S CLOCK, the
%   clock of the tracks) and uvec, its unit vector [east north up] - i.e.
%   INFO.CLICKS of LOCALISEPORPOISES with the clock offsets taken off. TIME
%   is a datenum.
%
%   [HTRACK, HLANDERS, HBEARINGS, HNOW, HOUT, HCIRCLE] =
%   PLOT_LOCTRACK_FRAME(...) returns the handles of a track, of the landers
%   and the lines between them, of the bearings of each lander (gobjects
%   where a lander heard nothing), of the latest positions, and of the
%   grey points outside MAXRANGE and its circle, for a legend.
%
%   Name-value parameters:
%     't0'            - datenum the colour scale is from [the first datestart]
%     'timelims'      - time limits of the colour scale (s from T0) [the tracks']
%     'bearingwindow' - the bearings of the clicks this long before TIME (s) [2]
%     'linelength'    - length of the bearing lines (m) [2*LIMS]
%     'lims'          - half width of the area plotted (m) [100]
%     'landernumbers' - number of each lander [1:n]
%     'colors'        - [n x 3] colour of each lander [GETDEFAULTCOLS]
%     'showcolorbar'  - the time colour bar [true]
%     'timecmap'      - colour map of the tracks ['Jet']
%     'maxrange'      - circle around the array; points of the tracks
%                       outside it are grey (PLOT_LOCTRACK_ARRAY) [[]]
%
%   See also PLOT_LOCTRACK_ARRAY, PLOT_LANDER_ARRAY, LOCALISEPORPOISES.

p = inputParser;
addParameter(p, 't0', [], @isnumeric);
addParameter(p, 'timelims', [], @isnumeric);
addParameter(p, 'bearingwindow', 2, @isnumeric);
addParameter(p, 'linelength', [], @isnumeric);
addParameter(p, 'lims', 100, @isnumeric);
addParameter(p, 'landernumbers', [], @isnumeric);
addParameter(p, 'colors', [], @isnumeric);
addParameter(p, 'showcolorbar', true, @islogical);
addParameter(p, 'timecmap', 'Jet');
addParameter(p, 'maxrange', [], @isnumeric);
parse(p, varargin{:});

lims = p.Results.lims;
cols = p.Results.colors;
if isempty(cols)
    cols = getdefaultcols();
end
linelength = p.Results.linelength;
if isempty(linelength)
    linelength = 2*lims;
end
t0 = p.Results.t0;
if isempty(t0) && ~isempty(loctracks)
    t0 = min([loctracks.datestart]);
end
timelims = p.Results.timelims;
if isempty(timelims) && ~isempty(loctracks)
    alltimes = cell2mat(cellfun(@(t) t(:), {loctracks.loctracktimes}, 'UniformOutput', false)');
    timelims = [min(alltimes) max(alltimes)];
end

% the tracks up to TIME, in s from T0, and the latest position of each
% track still running (heard within the bearing window)
past = loctracks([]);
latest = zeros(0, 3);
for i = 1:numel(loctracks)
    L = loctracks(i);
    t = L.loctracktimes(:)' + (L.datestart - t0)*86400;
    keep = t <= (time - t0)*86400;
    if ~any(keep)
        continue
    end
    L.xh = L.xh(:,keep);
    L.loctracktimes = t(keep);
    L.chi2 = L.chi2(keep);
    L.datestart = t0;
    past(end+1) = L; %#ok<AGROW>
    if (time - t0)*86400 - t(find(keep, 1, 'last')) <= p.Results.bearingwindow
        latest(end+1,:) = L.xh(1:3,end)'; %#ok<AGROW>
    end
end

[htrack, hlanders, ~, hout, hcircle] = plot_loctrack_array(past, landerxyz, meshdata, 't0', t0, ...
    'timelims', timelims, 'landernumbers', p.Results.landernumbers, 'lims', lims, 'colors', cols, ...
    'showlegend', false, 'showcolorbar', p.Results.showcolorbar, 'timecmap', p.Results.timecmap, ...
    'maxrange', p.Results.maxrange);
hold on

% the bearings of the clicks of the last BEARINGWINDOW seconds, one line
% (NaN separated) per lander
hbearings = gobjects(1, numel(clicks));
for d = 1:numel(clicks)
    in = clicks(d).t > time - p.Results.bearingwindow/86400 & clicks(d).t <= time;
    if ~any(in)
        continue
    end
    u = clicks(d).uvec(in,:);
    n = size(u, 1);
    xyz = nan(3*n, 3);
    xyz(1:3:end,:) = repmat(landerxyz(d,:), n, 1);
    xyz(2:3:end,:) = landerxyz(d,:) + linelength*u;
    c = cols(mod(d-1, size(cols, 1)) + 1, :);
    hbearings(d) = plot3(xyz(:,1), xyz(:,2), xyz(:,3), 'Color', [c 0.5], 'LineWidth', 0.75);
end

if isempty(latest)
    hnow = gobjects(0);
else
    hnow = plot3(latest(:,1), latest(:,2), latest(:,3), 'p', 'MarkerSize', 16, 'MarkerFaceColor', 'y', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 1);
end

% bearings to below the seabed or above the surface are cut off there
zlim([min(meshdata.z(:)) - 1, 1])
xlim([-1 1]*lims)
ylim([-1 1]*lims)
hold off

end
