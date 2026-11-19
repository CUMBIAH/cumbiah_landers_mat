function [htrack, hlanders, c, hout, hcircle] = plot_loctrack_array(loctracks, landerxyz, meshdata, varargin)
%PLOT_LOCTRACK_ARRAY Plots localised porpoise tracks with the landers of an array.
%
%   PLOT_LOCTRACK_ARRAY(LOCTRACKS, LANDERXYZ, MESHDATA) plots the tracks of
%   LOCALISEPORPOISES coloured by time, as PLOT_LOCTRACK_CORNWALL does,
%   over the seabed and the landers of PLOT_LANDER_ARRAY. Every track is
%   coloured on one time scale from T0, whichever encounter it is of, so
%   the tracks of a period which spans more than one encounter join up.
%
%   LOCTRACKS is a struct array of localised tracks (xh, loctracktimes,
%   datestart), LANDERXYZ the [n x 3] positions of the landers [east north
%   up] (m) and MESHDATA the seabed as x, y and z meshes.
%
%   With 'maxrange' a circle of that radius is drawn at the sea surface
%   around the middle of the landers, and the points of the tracks further
%   than that from it (horizontally) are grey, not coloured by time.
%
%   [HTRACK, HLANDERS, C, HOUT, HCIRCLE] = PLOT_LOCTRACK_ARRAY(...)
%   returns the handle of a track, of the landers and the lines between
%   them (PLOT_LANDER_ARRAY), of the time colour bar, of the grey points
%   outside MAXRANGE and of the circle (empty if there are none).
%
%   Name-value parameters:
%     't0'            - datenum the times are from [the first datestart]
%     'timelims'      - time limits of the colour scale (s from T0) [the tracks']
%     'landernumbers' - number of each lander [1:n]
%     'lims'          - half width of the area plotted (m) [100]
%     'colors'        - [n x 3] colour of each lander [GETDEFAULTCOLS]
%     'showlegend', 'showcolorbar' - [true]
%     'timecmap'      - colour map of the tracks ['Jet']
%     'maxrange'      - radius of the circle (m); [] for none [[]]
%     'rangecentre'   - [x y] centre of the circle (m) [the middle of the landers]
%     'outsidecolor'  - colour of the points outside the circle [0.6 0.6 0.6]
%     'bathycmap'     - colour map of the seabed ['bone']
%
%   See also PLOT_LANDER_ARRAY, PLOT_LOC_TRACK, PLOT_LOCTRACK_CORNWALL,
%   LOCALISEPORPOISES.

p = inputParser;
addParameter(p, 't0', [], @isnumeric);
addParameter(p, 'timelims', [], @isnumeric);
addParameter(p, 'landernumbers', [], @isnumeric);
addParameter(p, 'lims', 100, @isnumeric);
addParameter(p, 'colors', [], @isnumeric);
addParameter(p, 'showlegend', true, @islogical);
addParameter(p, 'showcolorbar', true, @islogical);
addParameter(p, 'timecmap', 'Jet');
addParameter(p, 'bathycmap', 'bone');
addParameter(p, 'maxrange', [], @isnumeric);
addParameter(p, 'rangecentre', [], @isnumeric);
addParameter(p, 'outsidecolor', [0.6 0.6 0.6], @isnumeric);
parse(p, varargin{:});

loctracks = loctracks_from(loctracks, p.Results.t0);
timelims = p.Results.timelims;
if isempty(timelims) && ~isempty(loctracks)
    alltimes = cell2mat(cellfun(@(t) t(:), {loctracks.loctracktimes}, 'UniformOutput', false)');
    timelims = [min(alltimes) max(alltimes)];
end

[hlanders, labels] = plot_lander_array(landerxyz, meshdata, 'landernumbers', p.Results.landernumbers, ...
    'lims', p.Results.lims, 'colors', p.Results.colors, 'showlegend', false, 'showcolorbar', false, ...
    'bathycmap', p.Results.bathycmap);

hold on
c = [];
hout = gobjects(0);
hcircle = gobjects(0);
maxrange = p.Results.maxrange;
if ~isempty(maxrange)
    centre = p.Results.rangecentre;
    if isempty(centre)
        centre = mean(landerxyz(:,1:2), 1);
    end
    % the points outside the circle are taken out of the coloured tracks
    % (NaN breaks the line of PLOT_LOC_TRACK) and plotted grey
    outside = zeros(3, 0);
    for i = 1:numel(loctracks)
        out = hypot(loctracks(i).xh(1,:) - centre(1), loctracks(i).xh(2,:) - centre(2)) > maxrange;
        outside = [outside, loctracks(i).xh(1:3,out)]; %#ok<AGROW>
        loctracks(i).xh(:,out) = NaN;
    end
    if ~isempty(outside)
        hout = scatter3(outside(1,:), outside(2,:), outside(3,:), 12, p.Results.outsidecolor, 'filled');
    end
    a = linspace(0, 2*pi, 361);
    hcircle = plot3(centre(1) + maxrange*cos(a), centre(2) + maxrange*sin(a), zeros(size(a)), ...
        'k--', 'LineWidth', 1);
end
if isempty(loctracks)
    htrack = gobjects(0);
else
    [htrack, c] = plot_loc_track(loctracks, 'timelimits', timelims, 'showtitle', false, ...
        'showcolourbar', p.Results.showcolorbar, 'timecmap', p.Results.timecmap);
end
% PLOT_LOC_TRACK leaves the colour map as the time colour map
colormap(gca, p.Results.bathycmap)
xlim([-1 1]*p.Results.lims)
ylim([-1 1]*p.Results.lims)
xlabel('Eastings (m)')
ylabel('Northings (m)')
zlabel('Depth (m)')
hold off

if p.Results.showlegend
    h = hlanders;
    if ~isempty(hcircle)
        h = [hcircle, h];
        labels = [{sprintf('%g m from the array', maxrange)}, labels];
    end
    if ~isempty(hout)
        h = [hout, h];
        labels = [{sprintf('Track beyond %g m', maxrange)}, labels];
    end
    if ~isempty(htrack)
        h = [htrack, h];
        labels = [{'Porpoise track'}, labels];
    end
    legend(h, labels, 'Location', 'northeastoutside');
end

end

function loctracks = loctracks_from(loctracks, t0)
% the times of every track in s from T0, not from the start of its own
% encounter
if isempty(loctracks)
    return
end
if isempty(t0)
    t0 = min([loctracks.datestart]);
end
for i = 1:numel(loctracks)
    loctracks(i).loctracktimes = loctracks(i).loctracktimes + (loctracks(i).datestart - t0)*86400;
    loctracks(i).datestart = t0;
end
end
