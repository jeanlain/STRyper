//
//  IndexImageView.h
//  STRyper
//
//  Created by Jean Peccoud on 02/04/2023.
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




#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// An `NSImageView` that can display alternative images.
///
/// An `IndexImageView` maintains several `NSImage` objects in its ``imageArray``,
/// and displays the image at the index returned by ``imageIndex``.
///
/// The main purpose of this class is to bind the ``imageIndex`` property to an integer key of an object that can be represented by an image.
/// This class therefore helps separating the view from the underlying model, avoiding `NSImage` properties in modeled objects, while still allowing binding to image views.
///
/// NOTE: setting the `image` of an `IndexImageView` will change its `imageIndex` to the index of the image in the `imageArray`,
/// or logs an error if the image is not in the array.
@interface IndexImageView : NSImageView

/// The alternative images that the view can show.
///
/// Setting this property sets the image present in the array at ``imageIndex`` as the view's `image`, if this index is within the array bounds,
/// Otherwise, `nil` is set as the view's `image` and an error is logged.
@property (nonatomic, copy) NSArray<NSImage *> *imageArray;
															
/// The index of the image from the ``imageArray`` to set as the view's image.
///
/// `nil` is set as the view's image and an error is logged
///  if no `NSImage` instance is present in ``imageArray`` at that index.
@property (nonatomic) NSUInteger imageIndex;


extern NSBindingName const ImageIndexBinding;


@end


NS_ASSUME_NONNULL_END
