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

@class Mmarker, Chromatogram, PanelFolder, Bin;
#import "Folder.h"
#import "Trace.h"

NS_ASSUME_NONNULL_BEGIN


/// A set of molecular markers that are analyzed conjointly.
///
///	A `Panel` allows analyzing chromatograms that represent the migration of amplicons from one or several molecular markers.
/// When a panel is applied to a sample (``Chromatogram``), a genotype is generated for each of the ``markers`` composing the panel.
/// This means that the sample has a ``Genotype`` object for each of these markers.
///
/// Although the `Panel` class inherits from ``Folder`` for practical reasons, a panel must not have ``Folder/subfolders``.
/// Its ``Folder/parent`` should be a ``PanelFolder`` object.
///
/// - Note: ``CodingObject/encodeWithCoder:``  and ``CodingObject/initWithCoder:``  are currently implement in the context of a ``SampleFolder`` unarchiving/archiving,
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
@property (nonatomic, nullable) NSSet <Mmarker *> *markers;


/// Returns the ``markers`` of a specific channel.
///
/// The markers returned are those  whose ``Mmarker/channel`` correspond to `channel`,  among the receiver's ``markers``.
/// - Parameter channel: The channel of the marker to be returned.
- (NSArray<Mmarker *> *)markersForChannel:(ChannelNumber)channel;

/// Returns a name that avoid duplicated names among the receiver's ``markers``.
///
/// The returned name is composed of "Marker " followed by an integer.
@property (nonatomic, readonly) NSString *_Nonnull proposedMarkerName;

/*********************************/

/// The samples using the panel.
///
/// The reverse relationship is ``Chromatogram/panel`` .
@property (nonatomic, nullable) NSSet <Chromatogram *> *samples;

/// Returns the receiver in an array.
///
/// This getter is similar to ``PanelFolder/panels`` to simplify code using ``PanelFolder`` and ``Panel`` objects
- (NSArray<Panel *> *)panels;


/************************Panel import / export *************/

/// A string representation of the panel, which can be used to export it to a text file.
///
/// See the ``STRyper`` user guide for details about the format of this string.
-(NSString *)exportString;


/// Sets bins for ``markers`` of the panel, using bin descriptions in a text file, and returns these bins.
///
/// The methods takes either a STRyper panel description file or a GeneMapper binset description file.
/// All markers identified in the file will have their current bins replaced. Other markers will not.
/// The method returns `nil` and sets the `error` if an error occurred decoding the file.
/// - Parameters:
///   - path: The path of the file describing the bins.
///   - error: On output, points to any error that occurred.
- (nullable NSSet<Bin*> *)updateBinsWithFile:(NSString *)path error:(NSError *__autoreleasing  _Nullable *)error;


/***************************/



/// some constant that avoid using strings in code, as these are often used in this application.
extern NSString * _Nonnull const PanelMarkersKey;
extern NSString * _Nonnull const PanelSamplesKey;
extern NSString * _Nonnull const PanelVersionKey;
extern NSArray const * _Nonnull channelColorNames;

@end



@interface Panel (CoreDataGeneratedAccessors)

-(void)addSamples:(NSSet *)samples;
-(void)removeSamples:(NSSet *)samples;

@end

NS_ASSUME_NONNULL_END
