//
//  SampleInspectorController.h
//  STRyper
//
//  Created by Jean Peccoud on 12/11/2022.
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
@class MainWindowController, Chromatogram;

NS_ASSUME_NONNULL_BEGIN

/// This singleton class manages the sample inspector: an outline view that shows information on selected samples (``Chromatogram``).
///
/// This view works like the file info panel of the Finder, in that information is divided in several sections that can be expanded.
///
/// The rows composing the outline view are designed in a nib, hence the view is not intended to be customised in code.
@interface SampleInspectorController : NSViewController <NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate> 

/// Returns the singleton object loaded from a nib.
+(instancetype)sharedController;

/// The samples on which the inspector should show information.
///
/// Setting this property automatically shows sample information.
@property (nonatomic) NSArray <Chromatogram *> *samples;

@end

NS_ASSUME_NONNULL_END
