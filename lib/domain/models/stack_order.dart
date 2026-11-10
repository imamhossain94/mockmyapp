/// Where a component sits in its screen's stack.
///
/// One integer per component — every shape, every device, and the captions as a
/// pair — read back to front: the lowest number is painted first and ends up
/// furthest away. This is the whole of the stacking model. There is no fixed
/// spine any more, so a device can be dragged over a caption and a caption
/// behind a phone, which the three-band arrangement this replaces could not
/// say: it could only place a shape *relative to* a device and a caption whose
/// own order was hard-coded.
///
/// The backdrop is the one thing with no z. It is not a competitor for a
/// position — it is the ground, always painted first, and nothing goes under
/// it.
library;

/// The default positions, spaced rather than consecutive, and spaced **in the
/// order the old fixed spine painted**.
///
/// That is what makes this change invisible to documents that predate it. A
/// shape defaulting to [kStackBehindFrames] falls behind a device defaulting to
/// [kStackFrames], which falls behind the captions at [kStackCaptions], exactly
/// as the spine used to hard-code — so a project file written last year, and a
/// `ScreenDoc` built in code that never mentions z at all, both come out
/// looking the way they always did. The defaults *are* the migration; there is
/// deliberately no migration pass anywhere.
///
/// The gaps of 100 are room to drop something between two neighbours without
/// renumbering. In practice `LayerStack.reorder` renumbers the whole stack
/// densely on every move, so a screen the user has actually arranged carries
/// consecutive values and never consults a default again.
const int kStackBehindFrames = 100;

/// Where a device lands when nothing has said otherwise.
const int kStackFrames = 200;

/// Over the devices, under the captions.
const int kStackOverFrames = 300;

/// Where the caption and subcaption sit as a pair.
const int kStackCaptions = 400;

/// Over everything, captions included — where a newly added shape goes, so it
/// is visible where it was dropped rather than hidden behind the phone.
const int kStackOverEverything = 500;
