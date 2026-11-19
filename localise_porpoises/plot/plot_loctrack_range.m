function plot_loctrack_range(loctracks, landerxyz, varargin)
%PLOT_LOCTRACK_RANGE Plots the range of the localised tracks from each lander against time.
%
%   PLOT_LOCTRACK_RANGE(LOCTRACKS, LANDERXYZ) plots, in a new tiled layout
%   in the current figure, one row per lander: the range (3D, m) from the
%   lander to every localised position against time, coloured by time as
%   PLOT_LOCTRACK_ARRAY colours the tracks, with an error bar (no caps) of
%   +/- one standard deviation of the range, from the spread of the
%   particles of the particle filter (LOCTRACKS.ERR, the st dev in x, y and
%   z, projected onto the direction from the lander).
%
%   LOCTRACKS is a struct array of localised tracks (xh, err,
%   loctracktimes, datestart) and LANDERXYZ the [n x 3] positions of the
%   landers [east north up] (m), as returned by LOCALISEPORPOISES.
%
%   Name-value parameters:
%     't0'            - datenum the times are from [the first datestart]
%     'timelims'      - time limits of the plot and colour scale (s from T0)
%                       [the tracks']
%     'landernumbers' - number of each lander [1:n]
%     'timecmap'      - colour map of the tracks ['Jet']
%     'maxrange'      - points further than this from the middle of the
%                       landers (horizontally, m) are grey, as in
%                       PLOT_LOCTRACK_ARRAY; [] for none [[]]
%     'outsidecolor'  - colour of those points [0.6 0.6 0.6]
%
%   See also PLOT_LOCTRACK_BEARINGS, PLOT_LOCTRACK_ARRAY, LOCALISEPORPOISES.

p = inputParser;
addParameter(p, 't0', [], @isnumeric);
addParameter(p, 'timelims', [], @isnumeric);
addParameter(p, 'landernumbers', [], @isnumeric);
addParameter(p, 'timecmap', 'Jet');
addParameter(p, 'maxrange', [], @isnumeric);
addParameter(p, 'outsidecolor', [0.6 0.6 0.6], @isnumeric);
parse(p, varargin{:});

nl = size(landerxyz, 1);
landernumbers = p.Results.landernumbers;
if isempty(landernumbers)
    landernumbers = 1:nl;
end
t0 = p.Results.t0;
if isempty(t0)
    t0 = min([loctracks.datestart]);
end
% every localised point, its particle st dev and its time in s from T0
pos = zeros(3, 0);
err = zeros(3, 0);
tpos = zeros(1, 0);
for i = 1:numel(loctracks)
    pos = [pos, loctracks(i).xh(1:3,:)]; %#ok<AGROW>
    err = [err, loctracks(i).err(1:3,:)]; %#ok<AGROW>
    tpos = [tpos, loctracks(i).loctracktimes(:)' + (loctracks(i).datestart - t0)*86400]; %#ok<AGROW>
end
timelims = p.Results.timelims;
if isempty(timelims)
    timelims = [min(tpos) max(tpos)];
end
cmap = colormap(p.Results.timecmap);
ci = round(1 + (size(cmap, 1) - 1)*min(max((tpos - timelims(1))/diff(timelims), 0), 1));
rgb = cmap(ci,:);
if ~isempty(p.Results.maxrange)
    centre = mean(landerxyz(:,1:2), 1);
    outside = hypot(pos(1,:) - centre(1), pos(2,:) - centre(2)) > p.Results.maxrange;
    rgb(outside,:) = repmat(p.Results.outsidecolor, sum(outside), 1);
end
[ucols, ~, group] = unique(rgb, 'rows');

tl = tiledlayout(nl, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for d = 1:nl
    v = pos - landerxyz(d,:)';
    r = vecnorm(v);
    % st dev of the range: the particle spread along the line from the lander
    sr = sqrt(sum((v./r).^2 .* err.^2, 1));

    nexttile
    hold on
    % the error bars, one NaN separated line per colour so there are not
    % thousands of line objects
    for g = 1:size(ucols, 1)
        k = find(group == g)';
        if isempty(k), continue, end
        x = [tpos(k); tpos(k); nan(size(k))];
        y = [r(k) - sr(k); r(k) + sr(k); nan(size(k))];
        plot(x(:), y(:), '-', 'Color', [ucols(g,:) 0.5], 'LineWidth', 0.75);
    end
    scatter(tpos, r, 10, rgb, 'filled');
    hold off
    xlim(timelims)
    ylim([0, max([r + sr, 10])*1.05])
    ylabel(sprintf('Range to lander %d (m)', landernumbers(d)))
    box on
    grid on
end
xlabel(tl, sprintf('Time from %s (s)', datestr(t0, 'yyyy-mm-dd HH:MM:SS')))
c = colorbar;
c.Layout.Tile = 'east';
c.Colormap = cmap;
clim(timelims);
c.Label.String = 'Track Time (seconds)';

end
