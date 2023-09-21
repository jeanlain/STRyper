//
//  MarkerView.h
//  STRyper
//
//  Created by Jean Peccoud on 05/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
//
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


NS_ASSUME_NONNULL_BEGIN

extern const float markerViewHeight;

/// A view that shows molecular marker above a ``TraceView``.
///
/// A `MarkerView` shows molecular marker (``Mmarker`` objects)  using ``RegionLabel`` objects.
///
/// It implements internal methods that allow the user to interact with marker labels
/// and to add new markers to the ``LabelView/panel`` show by the view, via click & drag.
///
/// A `MakerView` can make its ``traceView`` zoom to the range of a marker. It has two navigation buttons to that effect.
/// It can also set a specific mode allowing the creation of a new marker by click & drag.
///
/// IMPORTANT: a marker view must be the accessory view of a horizontal ruler view of a scrollview that has a ``TraceView`` as documentView.
///
/// Since it is subview of a ruler view, a marker view does not scroll, but makes as if it does by moving marker labels to reflect the scrolling position of its associated ``traceView``.
/// In effect, its ``LabelView/visibleOrigin`` properties is simply taken from its ``traceView``.
@interface MarkerView : LabelView

/// The ``TraceView`` object with which the view is associated.
///
/// This is the document view of the scrollview to which the marker view belongs.
@property (nonatomic, readonly, weak) TraceView *traceView;

/// The ``TraceView/channel`` (colour) that the ``traceView`` shows.
@property (nonatomic, readonly) NSInteger channel;
					
/// Returns a BaseRange that allows the `range` argument to fill in the visible rectangle of the view.
///
/// The returned value is computed such that the `range` does not overlap the navigation buttons of the view.
/// - Parameter range: the range for which the safe range should be computed.
- (BaseRange)safeRangeForBaseRange:(BaseRange)range;

/// Makes the view update its content (marker labels, button states) to reflect the ``LabelView/panel`` that it shows.
///
/// If the view has no ``LabelView/panel`` to show, a text box indicating "No marker to show"  is shown instead of marker labels, and the view's buttons are disabled.
- (void)updateContent;


/// Make the ``traceView`` zoom to the marker that is to the left of the visible range, and returns the corresponding region label
/// - Parameter sender: The object that sent this message.
///
/// If there is no suitable marker to move to, the method returns `nil`
-(nullable RegionLabel *)moveToPreviousMarker:(id)sender;


/// Make the ``traceView`` zoom to the marker that is to the right of the visible range, and returns the corresponding region label
/// - Parameter sender: The object that sent this message.
///
/// If there is no suitable marker to move to, the method returns `nil`
-(nullable RegionLabel *)moveToNextMarker:(id)sender;

@end

NS_ASSUME_NONNULL_END
