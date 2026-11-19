# Propagation: refraction and the lander slant angle

## Ray traced propagation in the localiser

`localiseporpoises(..., 'propagation', P)` predicts each lander's time delays
from the direction a click really arrives from, not a straight line. `P` is a
propagation struct, or a list of them (struct array or cell array). The one
closest in time to each encounter is used.

* `make_propagation_tables.m` ray traces every CastAway cast within 3 km of the
  array and saves `<cast>_propagation.mat` (struct `propagation`), plus all of them as
  `propagation_tables.mat`, in `Denmark/propagation/`.
* `make_propagation_table.m` builds one table: the direct path arrival elevation
  and travel time on a range (0.25–500 m) × depth grid for hydrophones at 17 m.
  Shadow cells (no direct ray) take the nearest traced value, and `shadow` marks them.
* `straight_propagation(time, c)` gives straight lines at one sound speed.
* `select_propagation` picks the struct closest in time.
* `propagation_delays` turns a struct into `f(x, h1, h2)`, which gives the
  delays of hydrophone pairs. The particle filter (`partice_filter_pam`,
  `'DelayFunction'`) and the start location (`trackstartloc_bounded`,
  `'delayFunction'`) use it.

The test is `localise_porpoises/_test/test_localise_propagation.m`.

## Refraction analysis

How much does refraction bias the slant angle a seabed lander measures, and so
the depth the straight-line localiser (`localiseporpoises`) gives a porpoise?

`run_refraction_analysis.m` ray traces the SonTek CastAway sound speed profiles
in `Denmark/All_SVP_CastAway_Data` with the MATLAB port of BELLHOP in AcTUP
v2.2L (`~/MATLAB-Drive/MATLAB/ACTUP`). By reciprocity, rays are launched from the
lander hydrophone and eigenrays found to porpoises at 5–250 m range and every
depth. Plots go to `Denmark/localisation/refraction_analysis/`.

| File | What it does |
|---|---|
| `run_refraction_analysis.m` | the refraction analysis script and plots |
| `slant_refraction_bias.m` | direct, surface and seabed eigenrays on a range × depth grid; slant bias and straight-line depth error |
| `actup_trace_rays.m` | writes a BELLHOP `.env`, reads it with the ACTUP readers and traces a ray fan with ACTUP `trace` |
| `load_site_svps.m` | loads every cast, distance from the array, gridded profile to the seabed |
| `read_castaway.m` | reads one CastAway `.csv` |

Assumptions: flat seabed at 17.2 m (bathymetry at the landers), hydrophone
0.5 m above it, range independent profile. An isovelocity run gives zero bias,
which checks the tracer and the eigenray search.

## Findings (Nov 2026)

* Three casts were taken within 0.5 km of the array: 25 June 2025 (two) and
  12 Sept 2025. None were taken during deployment 1 (Oct 2024).
* **June** (well mixed, c varies by 1–2 m/s): slant bias below 1°, and the
  straight-line depth is up to 1–4 m too shallow at 150–250 m. Small next to the
  bearing noise.
* **September** (thermocline at 10–14 m, c falls 11 m/s from 1488 to 1476 m/s):
  rays from the slow bottom layer turn back below about 7° elevation, so a
  porpoise in the upper layer can't be heard from below ~7°, however far away
  it is. The slant bias reaches 3° at 100 m and 5–6° at 150–200 m. The
  straight-line depth is then 6 m (100 m), 14 m (150 m) and 20 m (200 m) too
  shallow, so shallow porpoises get pushed to the surface beyond about 100 m.
* Of the 26 other casts, those with more than 4 m/s of sound speed change in the
  top 17 m give errors of 1–8 m at 150 m. So stratification, not location, is what matters.
* **The −10° cut-off is safe**: no direct path arrives below about +0.2° in any
  profile, so refraction never pushes a real click below the cut. But seabed
  echoes arrive above −10° (so they're kept) beyond ~45 m for a porpoise 10 m deep
  and ~100 m for one at the surface (~120 m in September).
* The real sound speed is 1476–1488 m/s, not the localiser's default 1500 m/s
  (1–1.5% on any range or delay that uses it).
