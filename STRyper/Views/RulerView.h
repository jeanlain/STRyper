//
//  RulerView.h
//  STRyper
//
//  Created by Jean Peccoud on 24/01/13.
//  Copyright (c) 2013 Jean Peccoud. All rights reserved.
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.




#import "TraceView.h"


/// A view that indicates the horizontal scale of a ``TraceView`` in base pairs.
///
/// A `RulerView` is the horizontal ruler of a scrollview whose document view is a ``TraceView``. It may have a ``MarkerView`` as its accessory view.
///
/// The ruler view shows tick-marks and text labels indicating sizes in base pairs, which constitute the X-axis of the plot containing the curves shown by the ``TraceView``,
/// or the range of markers shown by the ``MarkerView``.
///
/// If the trace(s) shown by the trace view belong to a sample that has no suitable sizing data (no size standard was, or could be, applied),
/// the view signifies that with some text instead of showing size labels. If no size standard is applied, the view can show a popup button
/// whose menu can be configured to apply a size standard.
///
/// - Important: A view of this class must be a horizontal ruler, and will not work as a vertical ruler.
/// The scrollview's document view must be a ``TraceView``.
///
/// This class does not override methods of `NSRulerView` to display the size labels, hence these methods have no effect on what the view shows.
/// The position of size labels is derived from properties and methods implement by ``TraceView`` and accounts for the _offset_ of markers (see ``STRyper`` guide and ``Genotype/offset``).
///
/// A `RulerView` can show a mobile label indicating a particular size, typically the position of the cursor on its client view.
/// It implements methods that allow the user to zoom in/out the trace view to a given range and sets a loupe cursor to denote this ability.
/// It overrides `scrollWheel:` to zoom to markers shown by the ``MarkerView`` via swipe.
@interface RulerView : NSRulerView <CALayerDelegate>

/// A position, in base pairs, to show on the ruler.
///
/// This method makes the ruler view display the `currentPosition` in a text label. This label is positioned at the `currentPosition`, in base pairs, with respect to the trace view.
///
/// This position is meant to represent the horizontal location of the mouse on the trace view or marker view.
///
/// This method has no effect if the sample shown by the trace view is not sized.
@property (nonatomic) float currentPosition;

/// Equivalent to ``LabelView/xForSize:``
- (float)xForSize:(float)size;

/// Equivalent to ``LabelView/sizeForX:``
- (float)sizeForX:(float)x;


/// Tells the view whether it needs to change its appearance (dark/light) to conform to the app theme.
///
/// As a ruler view use core animation layers, it must change their colors explicitly.
/// Setting this property to `YES` sets `needsDisplay` to `YES`.
///
/// This property is set as appropriate and avoids setting the colors of `CALayer` objects at each redisplay.
@property (nonatomic) BOOL needsChangeAppearance;

/// Tells that view that it needs to update the offsets of size labels to show within marker ranges.
///
/// Offset are updated at the beginning of `-drawRect`.
/// This property should return `YES` if the offset of one or several marker(s) shown by the trace view has/have changed.
@property (nonatomic) BOOL needsUpdateOffsets;

/// A button shown by the ruler view, which be configured to apply size standard.
///
/// Once this property is accessed, the visibility of the button
/// reflects whether the chromatogram of the``TraceView/trace`` shown by the trace view
/// has a size standard applied to it. When visible, the button is horizontally centered in the ruler view.
///
/// Typically the button's `menu` would be configured to show a list of available size standards,
/// with appropriate actions for menu items. By default, this menu has no item.
/// - Important: Once this property is accessed, the button will be visible if the sample(s) shown
/// in the trace view lack(s) a size standard. It is therefore important to configure the button's `menu`.
@property (nonatomic, readonly) NSPopUpButton *applySizeStandardButton;

/// The thickness of the ruler view = 14 pts.
extern const float ruleThickness;

@end
