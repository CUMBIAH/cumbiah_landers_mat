function [h, labels] = plot_lander_array(landerxyz, meshdata, varargin)
%PLOT_LANDER_ARRAY Plots the landers of an array over the seabed.
%
%   PLOT_LANDER_ARRAY(LANDERXYZ, MESHDATA) plots the seabed and the landers
%   as LOCATE_ARRAY does, without the drop positions: a filled marker at
%   each lander, on a line down to the seabed below it, and thin lines
%   between each pair of landers with their distance apart in the legend.
%
%   LANDERXYZ is the [n x 3] positions of the landers [east north up] (m)
%   and MESHDATA the seabed as x, y and z meshes, both as returned by
%   LOCALISEPORPOISES (INFO.SETTINGS.LANDERXYZ and INFO.MESHDATA).
%
%   [H, LABELS] = PLOT_LANDER_ARRAY(...) returns the handles of the landers
%   and the lines between them, and their legend labels, so a caller can
%   add them to a legend of its own.
%
%   Name-value parameters:
%     'landernumbers' - number of each lander [1:n]
%     'lims'          - half width of the area plotted (m) [100]
%     'colors'        - [n x 3] colour of each lander [GETDEFAULTCOLS]
%     'showlegend'    - [true]
%     'showcolorbar'  - a colour bar of the depth [true]
%     'bathycmap'     - colour map of the seabed ['bone']
%     'faceAlpha'     - transparency of the seabed [0.9]
%
%   The axes colour map is BATHYCMAP: anything plotted after it with RGB
%   colours (e.g. PLOT_LOC_TRACK) keeps its own colours, but call
%   colormap(BATHYCMAP) again after anything which changes the colour map.
%
%   See also LOCATE_ARRAY, PLOT_LOCTRACK_ARRAY, PLOT_LOCTRACK_FRAME.

p = inputParser;
addParameter(p, 'landernumbers', [], @isnumeric);
addParameter(p, 'lims', 100, @isnumeric);
addParameter(p, 'colors', [], @isnumeric);
addParameter(p, 'showlegend', true, @islogical);
addParameter(p, 'showcolorbar', true, @islogical);
addParameter(p, 'bathycmap', 'bone');
addParameter(p, 'faceAlpha', 0.9, @isnumeric);
parse(p, varargin{:});

nlander = size(landerxyz, 1);
landernumbers = p.Results.landernumbers;
if isempty(landernumbers)
    landernumbers = 1:nlander;
end
cols = p.Results.colors;
if isempty(cols)
    cols = getdefaultcols();
end
lims = p.Results.lims;

hold on
surf(meshdata.x, meshdata.y, meshdata.z, 'EdgeColor', 'none', 'FaceAlpha', p.Results.faceAlpha);
colormap(gca, p.Results.bathycmap)
% colour the depths of the part that is plotted, not the whole mesh
inview = abs(meshdata.x) <= lims & abs(meshdata.y) <= lims;
zrange = [min(meshdata.z(inview)) max(meshdata.z(inview))];
if numel(zrange) == 2 && diff(zrange) > 0
    clim(zrange)
end
if p.Results.showcolorbar
    cb = colorbar;
    cb.Label.String = 'Depth (m)';
end

h = gobjects(0);
labels = {};

% the landers, each on a line down to the seabed below it
zbed = interp2(meshdata.x, meshdata.y, meshdata.z, landerxyz(:,1), landerxyz(:,2));
for i = 1:nlander
    c = cols(mod(i-1, size(cols, 1)) + 1, :);
    if ~isnan(zbed(i))
        plot3(landerxyz([i i],1), landerxyz([i i],2), [zbed(i) landerxyz(i,3)], 'Color', c, ...
            'LineWidth', 1.5);
    end
    h(end+1) = plot3(landerxyz(i,1), landerxyz(i,2), landerxyz(i,3), 'o', 'MarkerSize', 10, ...
        'MarkerFaceColor', c, 'MarkerEdgeColor', 'k'); %#ok<AGROW>
    labels{end+1} = sprintf('Lander %d', landernumbers(i)); %#ok<AGROW>
end

% thin lines between each pair of landers
linestyles = {'-', '--', '-.', ':'};
pairs = nchoosek(1:nlander, 2);
for k = 1:size(pairs, 1)
    ab = pairs(k,:);
    h(end+1) = plot3(landerxyz(ab,1), landerxyz(ab,2), landerxyz(ab,3), ...
        linestyles{mod(k-1, numel(linestyles))+1}, 'Color', 'k', 'LineWidth', 0.75); %#ok<AGROW>
    labels{end+1} = sprintf('Lander %d to %d: %.1f m', landernumbers(ab), ...
        norm(diff(landerxyz(ab,:)))); %#ok<AGROW>
end

xlim([-lims, lims])
ylim([-lims, lims])
xlabel('Eastings (m)')
ylabel('Northings (m)')
zlabel('Depth (m)')

if p.Results.showlegend
    legend(h, labels, 'Location', 'northeastoutside');
end

end
