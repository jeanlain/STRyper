//
//  QLScrollView.h
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 05/11/2023.
//
//  Created by Jean Peccoud on 28/03/2022.
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



#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A scroll view that does not scroll under a certain condition.
///
/// The view will not scroll if its document view returns `NO` to `clipsToBounds`.
/// This is only design to work if the document view is a ``TracePreviewView``,
/// which returns `NO` to this message while it is being resized, and `YES` otherwise.
/// We do this because appkit sometime sees fit to scroll the document view when it is resized, which produces unwanted behavior.
@interface QLScrollView : NSScrollView

@end

NS_ASSUME_NONNULL_END
