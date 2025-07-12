//
//  CALayer+CALayerAdditions.h
//  STRyper
//
//  Created by Jean Peccoud on 03/07/2025.
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


#import <QuartzCore/QuartzCore.h>
@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

/// Convenience methods that `CALayer` does not implement.
@interface CALayer (CALayerAdditions)


/// Returns whether the layer, or one of its ancestor, is hidden or has zero opacity.
///
/// This method does not consider all scenarios that may cause the layer to be invisible.
/// For instance, it does not test wether the layer is outside the bounds of an ancestor that has `masksToBound` to `YES`.
@property (readonly) BOOL isVisibleOnScreen;


/// The visible portion of the layer in its own coordinate system, considering clipping by ancestors.
/// - Parameter layer: An ancestor of the receiver. If specified, the method will not consider ancestors past the `ancestor`.
- (CGRect)visibleRectInSuperLayer:(nullable CALayer *)ancestor;


/// Returns all `sublayers` of the layer and their descendants, recursively.
@property (readonly) NSSet <CALayer *> *allSublayers;

/// Draws the `string` of the layer at its position in a given layer.
///
/// This method can be used to avoid rasterizing the receiver's `string` for printing.
/// It tries to reproduce the layer attributes related to color, font, text wrapping, clipping and alignment.
/// It does not draw the layer background nor its border, and it does not consider the layer opacity, transforms or effects.
/// - Note:This method does nothing if the receiver is not a `CATextLayer`
/// and it is expected to be called within a `-drawRect:` call on its hosting view.
/// - Parameters:
///   - dirtyRect: The dirty rectangle of the `layer`. The method will not draw outside of it.
///   - viewLayer: The layer corresponding to the coordinate system of `dirtyRect`.
///   - clip: Wether the text should be clipped by the rectangle returned by ``visibleRectInSuperLayer:``.
///   - ctx: The graphics context to use. If `nil` the current context is used.
- (void) drawStringInRect:(NSRect)dirtyRect ofLayer:(CALayer *)layer withClipping:(BOOL) clip;


/// Returns an attributed string that tries to reproduce the layer attributes related to color, font, text wrapping, clipping and alignment.
///
/// This method returns `nil` of the layer does not inherit form `CATextLayer`.
@property (nullable, readonly) NSAttributedString *attributedString;


@end

NS_ASSUME_NONNULL_END
