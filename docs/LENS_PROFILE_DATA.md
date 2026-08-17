# Lens profile data

PhotoSuite includes a dependency-free adapter for the public Lensfun XML shape. It does not link to Lensfun or to a GPL metadata library.

Use Develop → Lens Profile → Import XML… to load a Lensfun database. PhotoSuite stores the selected profile identifier in the durable optics operation and maps the imported calibration to bounded distortion, vignetting, chromatic-aberration, and defringe values. The existing Core Image render graph then renders those values in the same graph as manual optics controls.

Lensfun data is not bundled in the main application. The Lensfun database is attributed as CC BY-SA 3.0 by default. The importer retains the supplied source, licence, notice, and source URL in the imported database and in every profile. If a distributor supplies another database, it must provide the matching attribution and licence notice.

The current adapter imports one representative calibration per lens. It converts the Lensfun polynomial families to bounded normalized values; it does not yet implement focal-length, aperture, focus-distance interpolation, camera crop-factor matching, full Lensfun model evaluation, or measured camera-profile selection. The bounded output is useful for a reproducible baseline, but it is not an Adobe-identical lens correction.
