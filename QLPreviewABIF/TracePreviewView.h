//
//  TracePreviewView.h
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
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



@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

/// A view that shows traces of a chromatogram in a quick look window.
///
/// This duplicates drawing methods of  TraceView.
@interface TracePreviewView : NSView

/// The traces data that the view plots.
@property (nonatomic, copy) NSArray<NSData *> *traces;

@end

NS_ASSUME_NONNULL_END
