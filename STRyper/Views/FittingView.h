//
//  FittingView.h
//  STRyper
//
//  Created by Jean Peccoud on 04/10/2022.
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
@import QuartzCore;
#import "Chromatogram.h"

NS_ASSUME_NONNULL_BEGIN

/// A view showing a plot representing the relationship between scan number and size, for a ``Chromatogram``.
///
/// This view draws a curve representing the relationship between scan number and size in base pairs for a ``Chromatogram``, using its ``Chromatogram/sizes`` attribute.
///
/// The result is a plot in which scan numbers represent the X axis and the corresponding sizes in base pairs the Y axis.
/// The plot takes the whole view frame, as the point of the curve for size 0 occupies its bottom-left corner.
/// The point of the curve corresponding to the last scan occupies the top-right corner of the frame.
///
/// The plot also shows cross-shaped points representing  ``Trace/fragments`` of the molecular ladder of the sample.
///
/// The plot has no graduated axis, but the view shows a horizontal dashed line and a text label
/// denoting the Y position (in baise pairs) of the mouse cursor.
///
/// The view has a tex field that is centered horizontally and vertically, which shows a message if the curve cannot be shown.
@interface FittingView : NSView  

													
/// The samples for which the view shows the fitting curve.
///
/// Setting this property makes the view draw the fitting curve if the array contains only one sample.
///
/// If no sizing is available for the sample of if the array is of length > 1, the ``textField`` is shown instead.
///
/// The array can contain several samples because the fitting view can be part of an inspector of selected samples (``SampleInspectorController`` class).
///
/// IMPORTANT: this property can be set and bound, but the getter returns `nil` as there is no ivar backing it.
@property (nullable, nonatomic) NSArray<Chromatogram *>* samples;


/// The text field that the view shows if it cannot show a fitting curve.
@property (readonly, nonatomic) NSTextField *textField;


/// The string that the ``textField`` shows when the ``samples`` array does not contain any sample.
///
/// The default value is "No sample selected".
@property (nonatomic) NSString *noSampleString;


/// The string that the ``textField`` shows when the ``samples`` array contains several samples.
///
/// The default value is "Multiple samples selected".
@property (nonatomic) NSString *multipleSampleString;


/// The string that the ``textField`` shows when the sample is not sized.
///
/// The default value is "Sample not sized".
@property (nonatomic) NSString *noSizingString;


/// The string that the ``textField`` shows if sizing failed for the sample.
///
/// The default value is "Sample sizing failed".
@property (nonatomic) NSString *failedSizingString;


@end

NS_ASSUME_NONNULL_END
