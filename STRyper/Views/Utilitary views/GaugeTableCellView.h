//
//  GaugeTableCellView.h
//  STRyper
//
//  Created by Jean Peccoud on 11/11/2022.
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



@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

/// An `NSTableCellView` that represents a number using a horizontal gauge.
///
///	A `GaugeTableCellView` represents a number whose value determines the width of a rectangular gauge (with rounded edges) showing at its bottom edge.
///
/// The gauge starts at the origin of the view frame and its width relative to the width of a view represents the ratio between the view's ``value``  and ``maxValue`` properties.
/// The color of the gauge also represents this ratio, using a blend of two colors.
@interface GaugeTableCellView : NSTableCellView <CALayerDelegate>
/// (This could class could be made a subclass of NSView, for more flexibility, but we use it in table cell views for now, so this avoids a subview).
/// This class also implement a method to disable animation the gauge its its -objectValue has changed, and NSView doesn't have this property.


/// The thickness of the gauge in points.
///
/// The default value is 3.5 points.
@property (nonatomic) float gaugeThickness;

/// The value that is represented by the width of the gauge.
///
/// When this value is ≤ 0, the gauge gets a width of 0.
///
/// The effective value that is set is constrained between 0 and  ``maxValue``.
@property (nonatomic) float value;

/// The value of the ``value`` property for which the gauge takes the whole view width.
@property (nonatomic) float maxValue;

/// The color of the gauge when ``value`` equals ``maxValue``.
///
/// By default, a green color is used.
@property (nonatomic) NSColor *maxValueColor;

/// The color of the gauge when ``value`` = 0.
///
/// By default, the system red color is used.
@property (nonatomic) NSColor *minValueColor;

/// Whether changes in gauge width should be animated.
///
/// The default value is YES.
@property BOOL animateGauge;

@end

NS_ASSUME_NONNULL_END
