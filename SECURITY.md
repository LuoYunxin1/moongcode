# Security and safety

MoonGCode is a static analysis tool. It never connects to a controller, opens a serial port, writes machine configuration, or executes G-code. A `PASS` report only means that the supported syntax and selected machine profile did not produce a finding.

Before physical use, verify the controller dialect, work offsets, tool length, fixtures, stock, feeds, spindle limits, emergency-stop procedure, and machine manufacturer guidance. Unsupported commands should remain errors unless an application explicitly opts into warning mode.

Report reproducible parser or audit bugs through a private security report when the issue could cause an unsafe recommendation. Include the smallest source program and machine profile that demonstrates the problem; do not include credentials or production machine identifiers.
