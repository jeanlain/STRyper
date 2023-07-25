//
//  Panel.h
//  STRyper
//
//  Created by Jean Peccoud on 13/02/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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

@class Mmarker, Chromatogram, PanelFolder;
#import "Folder.h"
#import "Trace.h"

NS_ASSUME_NONNULL_BEGIN


///	A container of molecular markers that may be analyzed for a sample.
///
/// A panel is applied to a sample (``Chromatogram``) to signify that it can be genotyped for molecular ``markers`` composing the panel.
/// This means that the sample should have a ``Genotype`` object for each of these markers.
///
/// Although it inherits from ``Folder`` for practical reasons, a panel should not have ``Folder/subfolders``.
/// Its ``Folder/parent`` should be a ``PanelFolder`` object.
///
/// Note: ``CodingObject/encodeWithCoder:``  and ``CodingObject/initWithCoder:``  are currently implement in the context of a ``SampleFolder`` unarchiving/archiving,
/// in that the ``Folder/parent`` of the receiver is encoded/decoded.
@interface Panel : Folder {
}

/************molecular markers *********/

/// The panel's molecular markers.
///
/// The reverse relationship is ``Mmarker/panel``.
///
/// This relationship is encoded/decoded in ``CodingObject/encodeWithCoder:``  /  ``CodingObject/initWithCoder:``.
/// It is also used in ``CodingObject/isEquivalentTo:``, to compare panels.
@property (nonatomic) NSSet <Mmarker *> *markers;


/// When the `markers` of a panel change, it posts a notification with this name to the default notification center.
extern NSNotificationName _Nonnull const PanelMarkersDidChangeNotification;


/// Returns the ``markers`` of a specific channel.
///
/// The markers returned are those  whose ``Mmarker/channel`` correspond to `channel`,  among the receiver's ``markers``.
/// - Parameter channel: The channel of the marker to be returned.
- (NSArray *)markersForChannel:(ChannelNumber)channel;

/// Returns a name that avoid duplicated names among the receiver's ``markers``.
///
/// The returned name is composed of "Marker " followed by an integer.
@property (nonatomic, readonly) NSString *_Nonnull proposedMarkerName;

/*********************************/

/// The samples using the panel.
///
/// The reverse relationship is ``Chromatogram/panel`` .
@property (nonatomic) NSSet <Chromatogram *> *samples;

/// When the `samples` of a panel change, it posts a notification with this name to the default notification center
extern NSNotificationName _Nonnull const PanelSamplesDidChangeNotification;

/// A core data attribute that can be used to denote the version of the panel.
///
/// This number can be modified if the ``markers`` composing the panel change.
@property (nonatomic) NSNumber *version;
/// STRyper no longer uses this attribute.

/************************Panel import / export *************/

/// A string representation of the panel, which can be used to export it to a text file.
///
/// See the``STRyper`` user guide for details about the format of this string.
-(NSString *)stringRepresentation;

/// Returns a panel decoded from a text file.
///
/// This method returns `nil` and sets the `error` argument if there was a error preventing decoding, or a validation error.
/// - Parameters:
///   - path: The path of the file to import. Its format is described in the ``STRyper`` user guide.
///   - managedObjectContext: The context in which the imported panel will be materialized.
///   - error: On output, any error that prevented the import.
+ (nullable instancetype) panelFromTextFile:(NSString *)path insertInContext:(NSManagedObjectContext *)managedObjectContext error:(NSError *__autoreleasing  _Nullable *)error;

/***************************/



+ (NSArray *)sortByStart:(NSArray*) regions;


/// some constant that avoid using strings in code, as these are often used in this application.
extern NSString * _Nonnull const PanelMarkersKey;
extern NSString * _Nonnull const PanelSamplesKey;
extern NSString * _Nonnull const PanelVersionKey;
extern NSArray const * _Nonnull channelColorNames;

@end




NS_ASSUME_NONNULL_END
