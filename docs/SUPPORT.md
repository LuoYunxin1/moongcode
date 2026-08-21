# Supported dialect

Supported: comments in parentheses and after `;`, optional `%` program delimiters, line numbers, checksums, `G0/G1/G2/G3/G4`, `G17/G18/G19`, `G20/G21`, `G90/G91`, `G90.1/G91.1`, XYZ/IJK/R/P/F/S/T, and M0/M1/M2/M3/M4/M5/M30.

Unsupported by design: controller macros, variables, subprogram calls, canned cycles, tool compensation, work-offset mutation, probing, cutter compensation, custom M-codes, serial protocols, and firmware-specific dialect extensions. Unsupported words are errors unless warning mode is explicitly selected by the caller.
