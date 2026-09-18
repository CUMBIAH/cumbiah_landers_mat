function sitedir = getlandersuperfolder(site)
%GETLANDERSUPERFOLDER Root of one site's CUMBIAH lander dataset.
%
%   SITEDIR = GETLANDERSUPERFOLDER() returns the folder holding the Denmark
%   lander data - the per lander folders, the GPS tracks, the bathymetry, the
%   CastAway casts and the lander settings spreadsheet. Everything else in
%   this project is located relative to it.
%
%   SITEDIR = GETLANDERSUPERFOLDER(SITE) returns the folder for SITE instead,
%   e.g. 'Germany'. Each site has its own folder alongside the others under
%   'landers', with the same layout inside, so SITE is simply the name of
%   that folder. It defaults to 'Denmark'. Nothing checks that the folder
%   exists, in keeping with GETLANDERPATHS.
%
%   The Dropbox root differs between machines, so it comes from
%   GETSUPERFOLDER. Note that the Dropbox folder is '2026-27_CUMBIAH' (the
%   funding years) while the MATLAB folder these functions live in is
%   '2024-25_CUMBIAH' (the field seasons) - they are the same project.
%
%   Example:
%       d = getlandersuperfolder();            % .../landers/Denmark
%       d = getlandersuperfolder('Germany');   % .../landers/Germany
%
%   See also GETSUPERFOLDER, GETLANDERPATHS, CUMBIAHLANDERTABLE.

if nargin < 1 || isempty(site)
    site = 'Denmark';
end
if ~(ischar(site) || (isstring(site) && isscalar(site)))
    error('getlandersuperfolder:badSite', ...
        'SITE must be the name of a site folder, e.g. ''Denmark''.');
end

sitedir = fullfile(getsuperfolder, '2026-27_CUMBIAH', 'landers', char(site));

end
