//
//  PreviewViewController.h
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
//
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

/// The object that controls the quick look preview.
@interface PreviewViewController : NSViewController

/// The information shown about a sample on top of the preview pane.
///
/// This property is bound to the value of a text field, which shows sample name, plate name and well, if available.
@property (nonatomic, readonly) NSString *sampleInformation;

@end
