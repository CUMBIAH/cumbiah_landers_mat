function denmarkdir = getlandersuperfolder()
%GETLANDERSUPERFOLDER Root of the CUMBIAH Denmark lander dataset.
%
%   DENMARKDIR = GETLANDERSUPERFOLDER() returns the folder holding the Denmark
%   lander data - the per lander folders, the GPS tracks, the bathymetry, the
%   CastAway casts and the lander settings spreadsheet. Everything else in
%   this project is located relative to it.
%
%   The Dropbox root differs between machines, so it comes from
%   GETSUPERFOLDER. Note that the Dropbox folder is '2026-27_CUMBIAH' (the
%   funding years) while the MATLAB folder these functions live in is
%   '2024-25_CUMBIAH' (the field seasons) - they are the same project.
%
%   See also GETSUPERFOLDER, GETLANDERDATAPATHS, CUMBIAHLANDERTABLE.

denmarkdir = fullfile(getsuperfolder, '2026-27_CUMBIAH', 'landers', 'Denmark');

end
