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
#import "TraceOutlineView.h"
#import "SourceListController.h"
#import "TableViewController.h"


/// A singleton class that manages the viewer showing chromatogram traces or molecular markers in ``STRyper``.
///
/// This class manages the viewer whose rows contain ``TraceView`` instances.
/// The ``TableViewController/contentArray`` property determines what the trace views show: ``Chromatogram``,  ``Genotype``  or ``Mmarker`` objects.
/// If the content array contains ``Bin`` objects, their ``Bin/marker`` is represented by a row and the labels corresponding to bins are highlighted on the trace view.
///
/// When it shows genotypes or chromatograms, and depending on the ``stackMode`` property, the viewer also shows "regular" table rows with sample metadata,
/// like the table managed by the ``SampleTableController``.
@interface DetailedViewController : TableViewController <TraceViewDelegate, TraceOutlineViewDelegate, NSOutlineViewDataSource>


/// Whether the viewer shows genotypes (the ``TableViewController/contentArray`` contains ``Genotype`` objects).
@property (readonly) BOOL showGenotypes;

/// Whether the viewer shows markers (the ``TableViewController/contentArray`` contains ``Mmarker`` objects).
@property (readonly) BOOL showMarkers;
															
/// An integer that specifies how the viewer displays traces when it shows chromatograms.
typedef NS_ENUM(NSUInteger, StackMode) {
	
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
} ;


/// The mode of stacking traces in rows of the viewer.
///
/// Setting this property reloads the viewer if it shows samples (that is, if ``TableViewController/contentArray`` contains ``Chromatogram`` objects).
@property (nonatomic) StackMode stackMode;


/// Whether genotypes of a given marker should be stacked in the same row.
///
/// This property has a visible effect only when the ``showGenotypes`` returns `YES`.
@property (nonatomic) BOOL stackGenotypes;

/// The desired number of rows showing traces to fit the visible height of the viewer.
///
/// The effective value is constrained to 1...5. Changing it resize the rows vertically.
///
/// Depending on the height of visible area of the viewer, and given that the height of rows is
/// constrained to [40, 1000] points,  this number may differ from effective number of rows that can fit the view.
@property (nonatomic) NSUInteger numberOfRowsPerWindow;

/// Whether the ``TraceView/visibleRange`` of trace views should be synchronized between rows.
///
/// Synchronization is effective only when the viewer shows chromatograms (``showMarkers`` and ``showGenotypes`` return `NO`).
@property (nonatomic) BOOL synchronizeViews;

/// Records the synchronized visible range of trace views in the user defaults
-(void)recordReferenceRange;

/// An integer that specifies how the vertical scale of trace views is managed.
typedef NS_ENUM(NSUInteger, TopFluoMode) {
	
	/// The  ``TraceView/topFluoLevel`` property of traces views is synchronized.
	topFluoModeSynced = 0,
	
	/// The  ``TraceView/topFluoLevel``  property is set independently for each trace views.
	topFluoModeIndependent = 1,
	
	/// The ``TraceView/autoScaleToHighestPeak`` property of trace views is set to `YES`.
	topFluoModeHighestPeak = 2,
};

/// The mode by which the vertical scale of trace views is managed.
@property (nonatomic) TopFluoMode topFluoMode;

/// Shows the system print panel to print traces, or an alert if there is nothing to print.
-(IBAction)print:(id)sender;

@end
