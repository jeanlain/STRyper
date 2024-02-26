//
//  OutlineViewController.h
//  STRyper
//
//  Created by Jean Peccoud on 26/08/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



#import "TraceView.h"
#import "SourceListController.h"
#import "TableViewController.h"
#import "TraceViewDelegate.h"


/// A singleton class that manages the detailed view showing traces or markers.
///
/// This class manages the detailed view whose rows contain ``TraceView`` instances.
/// The ``contentArray`` property determines what the trace views show: ``Chromatogram``,  ``Genotype``  or ``Mmarker`` objects.
///
/// When it shows genotypes or chromatograms, and depending on the ``stackMode`` property, the detailed view also shows "regular" table rows with sample metadata, like the table managed by the ``SampleTableController``.
@interface DetailedViewController : TableViewController <TraceViewDelegate>


/// The samples (``Chromatogram`` objects), genotypes (``Genotype`` objects)  or markers (``Mmarker`` objects) shown in the detailed view.
///
/// Setting this property reloads the content of the detailed view. The provided array must contain objects from only one of the classes listed above.
///
/// NOTE: if there are too many objects in the array (>400 samples or >1000 genotypes), no item will be shown in the detailed view.
/// A button will be shown instead, whose action is ``loadContent:``, and the content is set to an array containing only `NSNull`.
@property (nonatomic) NSArray *contentArray;

/// Forces the controller to set its ``contentArray`` to the  selected samples/genotypes/markers and to show them in the detailed view.
/// - Parameter sender: The object that sent the message. It is not used by the method.
///
/// This methods considers that the content set by setting ``contentArray`` may not be loaded if it contains to many elements.
-(IBAction)loadContent:(NSButton *)sender;
															
/// An integer that specifies how the detailed view displays traces when its show samples.
typedef enum StackMode : NSUInteger {
	
	/// Each trace is shown in a separate row.
	/// Sample metadata are shown in "regular" rows above traces (for each sample).
	stackModeNone = 0,
	
	/// Each row shows the traces of a given sample, hence traces from different channels are stacked in the same row.
	stackModeChannels = 1,
	
	/// All traces of a given channel show in the same row, hence traces from different samples are stacked.
	///
	/// In this mode, there are no "regular" row showing sample information, and as many rows as visible channels.
	/// Hence, column headers are replaced by a text indicated how many samples are stacked per row.
	stackModeSamples = 2,
} StackMode;


/// The mode of stacking traces in rows of the detailed view.
///
/// Setting this property reloads the detailed view if it shows samples (that is, if ``contentArray`` contains ``Chromatogram`` objects).
@property (nonatomic) StackMode stackMode;


/// The number of rows showing traces to fit the visible height of the detailed view.
///
/// The effective value is constrained to 1...5.
@property (nonatomic) NSUInteger numberOfRowsPerWindow;

/// Whether the ``TraceView/visibleRange`` of trace views should be synchronized.
@property (nonatomic) BOOL synchronizeViews;

/// Records the synchronized visible range of trace views in the user defaults
-(void)recordReferenceRange;

/// An integer that specifies how the vertical scale of trace views is managed.
typedef enum TopFluoMode : NSUInteger {
	
	/// The  ``TraceView/topFluoLevel`` property of traces views is synchronized.
	topFluoModeSynced = 0,
	
	/// The  ``TraceView/topFluoLevel``  property is set independently for each trace views.
	topFluoModeIndependent = 1,
	
	/// The ``TraceView/autoScaleToHighestPeak`` property of trace views is set to `YES`.
	topFluoModeHighestPeak = 2,
} TopFluoMode;

/// The mode by which the vertical scale of trace views is managed.
@property (nonatomic) TopFluoMode topFluoMode;


@end
