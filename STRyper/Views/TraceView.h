//
//  TraceView.h
//  STRyper
//
//  Created by Jean Peccoud on 27/08/12.
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



@import QuartzCore;
#import "LabelView.h"
#import "Chromatogram.h"
#import "Trace.h"
#import "Panel.h"
#import "TraceViewDelegate.h"

@class MarkerView, Genotype, VScaleView;

NS_ASSUME_NONNULL_BEGIN

/// A view that shows traces and associated labels (``ViewLabel`` objects) for peaks, fragments, markers and bins.
///
/// A trace view shows the fluorescence data of ``Trace`` objects as curves whose colors reflect the trace ``Trace/channel``.
/// The view draws a plot in which the x axis represent the size in base pairs, and the y axis the trace fluorescence level, using the view coordinates system.
/// By default, the trace view has its bound y origin set to -0.5, such that the 1-point-thick curve at a fluorescence level of 0 sits just above the bottom edge.
///
/// This view also shows ``Chromatogram/offscaleRegions`` as colored rectangles behind the curves.
///
/// A trace view can show several traces at once. These could be all traces of a given  ``Trace/chromatogram`` ("sample"), or of several samples.
/// Alternatively, this view can show a marker only (no trace).
///
/// - Important: A trace view must be a document view of an `NSScrollView` (subclass). It will not work otherwise.
/// It is designed to scroll only horizontally. It resizes itself to fit its clipview vertically.
///
/// A trace view interacts with a ``MarkerView`` to show the range of molecular markers of its ``LabelView/panel``, a ``RulerView`` to indicate the horizontal scale it base pairs,
/// and a ``VScaleView`` to show the vertical scale in fluorescence units.
///
/// This view implements internal methods allowing the user to add/edit bins (class ``Bin``) by click & drag and to add a missing peak to a trace by right-clicking.
@interface TraceView : LabelView <CALayerDelegate>

/// The view showing the fluorescence level representing the vertical scale of of the curves plotted by the trace view.
///
/// This view corresponds to "left ruler in the ``STRyper`` user guide, and it is set by the ``TraceScrollView``, of which is is a subview.
/// It is normally positioned on the left of the trace view, which it overlaps.
///
/// This view is hidden if the trace view does not show traces.
@property (weak, nonatomic) VScaleView *vScaleView;

/// The horizontal ruler view of the enclosing ``TraceScrollView``.
///
/// This view shows the horizontal scale of the trace view, in base pairs.
/// It is created only if is the trace view is in a scroll view.
@property (nonatomic, readonly, nullable, weak) RulerView *rulerView;

/// The view showing the range of markers
///
/// This is the accessory view of the ``rulerView``, which shows on top of the trace view.
/// The markerView is created only if is the trace view is in a scroll view.
@property (readonly, nonatomic, nullable, weak) MarkerView *markerView;

///The trace view's delegate.
@property (nullable, weak, nonatomic) IBOutlet id <TraceViewDelegate> delegate;
																	

# pragma mark - loading and displaying content

/// Makes the view load and show some content.
///
/// The `object` must either be a ``Trace``, an array of ``Trace`` objects of the same ``Trace/channel``,
/// an object of class ``Genotype``, ``Mmarker`` or ``Chromatogram``.
/// The managed object context of any loaded Chromatogram, Trace, Marker or Genotype must be the view context of the application.
///
/// The view will only load the first 400 traces of the array if it contains more.
///
/// If the `object` is a chromatogram, the view will show its  ``Chromatogram/traces``  (depending of the ``displayedChannels``).
///
/// If the `object` is a genotype, the view will show the trace associated with the ``Mmarker/channel`` of the genotype's ``Genotype/marker``,
/// and will set its ``visibleRange``  to the range of this marker.
///
/// If the `object` is a marker, the view will show no trace and and will set its ``visibleRange``  to the range of the marker.
/// The marker's ``Mmarker/bins`` will also be shown if it has any.
/// - Parameter object: The content to show in the view.
-(void)loadContent:(id)object;

/// The trace(s) that the view shows.
///
/// This array will contain no more than 400 traces.
@property (nonatomic, readonly, nullable) NSArray<Trace *> *loadedTraces;

/// The longest trace (in base pairs) among the ``loadedTraces``, or `nil`  if there is none.
///
/// In most cases, the view shows a single trace, so having a direct pointer it is useful.
/// This property helps the implementation even if the view shows several traces.
@property (nonatomic, readonly, nullable, weak) Trace *trace;

/// The genotype the view has loaded .
@property (nonatomic, readonly, nullable) Genotype *genotype;

/// The marker associated with the view.
///
/// If the view has loaded a genotype, it is the genotype's ``Genotype/marker``.
/// If the view has loaded a marker, it is the marker itself.
/// Otherwise this property is `nil`.
@property (nonatomic, readonly, nullable) Mmarker *marker;

/// The ``Trace/channel`` of the trace(s) or marker shown by the view, from 0 to 4.
///
/// The returned value is -1 if the view shows traces from different channels (i.e., if a ``Chromatogram`` was loaded).
/// This property may not reflect the ``displayedChannels`` property.
@property (nonatomic, readonly) ChannelNumber channel;



# pragma mark - ViewLabel management

/// The fragment labels that the view shows.
///
/// These labels represent the ``Trace/fragments`` of the view's ``trace``.
/// The view only shows fragment labels it it shows a single trace.
@property (nonatomic, readonly, nullable) NSArray<FragmentLabel *> *fragmentLabels;

/// The labels representing peaks when hovered (vertical line and tooltips) or clicked, if the view shows a single trace.
@property (nonatomic, readonly, nullable) NSArray<PeakLabel *> *peakLabels;

/******** colors that adapt to the view appearance and which are use by view labels ******/
///
/// The view updates these properties within its `updateLayer` method after a change of appearance.
/// Hence, view labels can set them for their layers outside of `drawRect:` or `updateLayer` calls
/// (they don't have to call `setNeedsDisplay:` on their view whenever they need to apply a color).
/// The colors are retained and released by the view.
/// Do not release them unless you retain them first (which would be unnecessary).

/// The color for fragment labels that are not alleles.
@property (readonly, nonatomic) CGColorRef fragmentLabelBackgroundColor;

/// The color for fragment labels that are alleles.
///
/// The color reflects the view's ``channel`` and is `NULL` if the channel is invalid.
@property (readonly, nonatomic) CGColorRef alleleLabelBackgroundColor;

/// The color used for the text of fragment labels (including alleles).
@property (readonly, nonatomic) CGColorRef fragmentLabelStringColor;

/// The color used by bin labels when not hovered.
@property (readonly, nonatomic) CGColorRef binLabelColor;

/// The color used by bin labels when hovered.
@property (readonly, nonatomic) CGColorRef hoveredBinLabelColor;

/// The color of the edges of bin labels and ``LabelView/markerLabels``  to signify that they can be resized.
@property (readonly, nonatomic) CGColorRef regionLabelEdgeColor;

/// The color showing behind bin names in bin labels.
@property (readonly, nonatomic) CGColorRef binNameBackgroundColor;

/// The color showing behind bin names in bin labels that are hovered.
@property (readonly, nonatomic) CGColorRef hoveredBinNameBackgroundColor;

/// The color of the marker region when bins are being added/edited/moved or when the marker offset is being adjusted.
@property (readonly, nonatomic) CGColorRef traceViewMarkerLabelBackgroundColor;

/// The color denoting the allowed range of a marker being resized/moved when moving bins or adjusting the marker offset.
@property (readonly, nonatomic) CGColorRef traceViewMarkerLabelAllowedRangeColor;

																		 
/// Tells the view whether its ``fragmentLabels`` must be repositioned.
///
/// This method accounts for the fact that the position of a ``FragmentLabel`` depends on the vertical scale and peak height, as opposed to other labels.
/// Hence, only these labels may need to be repositioned in certain conditions.
@property (nonatomic) BOOL needsRepositionFragmentLabels;


/// Action that can be sent by a control to rename an item represented by a label.
///
/// Currently, only alleles are renamed by this action.
/// The view sends ``ViewLabel/doubleClickAction:`` to the selected ``FragmentLabel`` if it
/// represents an allele, scrolling to show the allele if necessary.
/// The view also performs validation on a menu item that has this action.
/// - Parameter sender: The object that sent the message, it is ignored by the method.
- (IBAction)rename:(id)sender;

# pragma mark - display settings

///********************** display settings properties (KVO compliant) that have visual effects if changed******************

/// Whether off-scale regions of the ``trace``'s ``Trace/chromatogram`` are shown (as colored rectangles).
///
/// See ``Chromatogram/offscaleRegions``for more information.
///
/// The default value is `YES`.
@property (nonatomic) BOOL showOffscaleRegions;

/// Whether the views shows tooltips indicating information about the ``trace``'s ``Trace/peaks``.
///
/// The default value is `NO`.
@property (nonatomic) BOOL showPeakTooltips;

/// Whether  the view's bin labels that are not ``ViewLabel/enabled`` should be shown.
///
/// The default value is `YES`. When it is `NO`, the bin labels that are not ``ViewLabel/enabled`` have their ``ViewLabel/hidden`` property set to `YES`.
@property (nonatomic) BOOL showDisabledBins;

/// Whether the view plots raw fluorescence data.
///
/// If `YES`, the view uses the trace's ``Trace/rawData`` property to draw curves.
/// Otherwise, it uses the fluorescence data with subtracted baseline.
///
/// The default value is `NO`.
@property (nonatomic) BOOL showRawData;

/// If ``showRawData`` is `NO`, whether the view draws curves with subtracted baseline maintaining peak heights.
///
/// The default value is `YES`.
@property (nonatomic) BOOL maintainPeakHeights;

/// Whether the view automatically adjusts its ``vScale`` so that the tip of the highest visible peak is close to its top edge.
///
/// The default value is `NO.
@property (nonatomic) BOOL autoScaleToHighestPeak;

/// Whether peaks resulting from crosstalk should painted with the color of the channel that induced crosstalk.
///
/// Peaks resulting from crosstalk are painted only if the view shows ``peakLabels``, hence if a single ``Trace`` was loaded.
/// The default value is `YES`.
@property (nonatomic) BOOL paintCrosstalkPeaks;

/// Whether peaks resulting from crosstalk should be ignored by ``topFluoForRange:``.
///
/// The default value is `NO`.
@property (nonatomic) BOOL ignoreCrosstalkPeaks;

/// The ``visibleRange`` that the view takes by default.
///
/// The `len` component cannot be negative and `start` + `len` is constrained to [2; 1000]
@property (nonatomic) BaseRange defaultRange;

/// The channels the view displays if it has loaded a sample with ``loadContent:``.
///
/// The value of this property has an effect on the traces shown by the view only if the view has loaded a sample.
@property (nonatomic, copy) NSArray<NSNumber *>* displayedChannels;

/// strings used for binding the properties defined above
extern const NSBindingName ShowOffScaleRegionsBinding,
ShowBinsBinding,
ShowRawDataBinding,
MaintainPeakHeightsBinding,
AutoScaleToHighestPeakBinding,
DisplayedChannelsBinding,
PaintCrosstalkPeakBinding,
IgnoreCrossTalkPeaksBinding,
DefaultRangeBinding,
ShowPeakTooltipsBinding;


# pragma mark - managing the visible range of the trace(s)

/// The left contentInset of the receiver's `NSScrollView`.
///
/// This property determines the ``visibleOrigin`` and reflects the ``VScaleView/width`` of the ``vScaleView``.
@property (nonatomic) float leftInset;

/// The x origin of the visible rectangle of the view.
///
/// The visible rectangle excludes the region that is masked by the ``vScaleView``,
/// hence it does not start at the bounds origin of the view's clipView if the ``vScaleView`` is visible,
/// hence if ``leftInset`` is positive.
@property (nonatomic, readonly) float visibleOrigin;

/// The range in base pairs that that the view shows in its visible rectangle.
///
/// The `len` component of the range should normally be positive. If negative, its value will be added to the `start` component, and then inverted.
///
/// The `start` component of the range is used to set the ``visibleOrigin`` of the trace view. Its `len` conditions the horizontal scale ``LabelView/hScale`` of the view.
/// Settings this  property thus makes the view show the range in its visible rectangle, resizing and scrolling the view as necessary.
///
/// Setting a new value for this property  sends `-viewDidChangeVisibleRange:`  to the view's ``delegate``. If the value hasn't changed, the delegate is not notified. The view also sets this value for the ``Trace/visibleRange`` of each trace of its ``loadedTraces``.
///
/// This allows other views to show this trace at the visible range that was set by the user, accounting for the fact that a trace may move between views in the reuse queue of an `NSTableView`.
@property (nonatomic) BaseRange visibleRange;
														
/// Sets the view's ``visibleRange`` without notifying its ``delegate``.
///
/// This method can be used by the ``delegate`` to synchronize positions between views without causing recursive notifications.
- (void)setVisibleRangeAndDontNotify:(BaseRange)range;
															
/// Sets the the view's ``visibleRange`` with optional animation.
///
/// If `animate` is `YES`, this method send  `-viewDidChangeVisibleRange:`  to the view's ``delegate`` at each step of the animation.
///
/// If animate is `NO`, this method just calls the setter of ``visibleRange``.
/// - Parameters:
///   - visibleRange: The visible range the view should have.
///   - animate: Whether the change in view geometry should be animated.
- (void)setVisibleRange:(BaseRange)visibleRange animate:(BOOL)animate;


/// Performs `-scrollRectToVisible:rect` with optional animation and returns if any scrolling was made.
///
/// The method updates the view's ``visibleRange``. 
/// - Parameters:
///   - rect: The rectangle that should be visible.
///   - animate: Whether the scroll should be animated.
- (BOOL)scrollRectToVisible:(NSRect)rect animate:(BOOL)animate;


/// Performs `-scrollPoint:point` with optional animation and returns if any scrolling was made.
/// - Parameters:
///   - point: The pont that should become the visible origin of the view.
///   - animate: Whether the scroll should be animated.
- (void)scrollPoint:(NSPoint)point animate:(BOOL) animate;
		
/// Zooms the view to a point given a zoom factor.
///
/// This method can be used to implement zooming with the scroll wheel or trackpad, using the cursor's horizontal position for `xPosition`.
/// - Parameters:
///   - xPosition: The horizontal position in the view coordinate system that is the focus of the zoom.
///   - zoomFactor: The ratio in view widths after / before the zoom.
///   The ratio cannot be lower than 0.01 and is constrained such that the view's ``visibleRange`` is not wider that a certain length.
///   - animate: Whether the change in view geometry should be animated. If `YES`, this method calls ``setVisibleRange:animate:``.
- (void)zoomTo:(float)xPosition withFactor:(float)zoomFactor animate:(BOOL)animate;
									
/// Zooms the view from a start and end positions defined in base pairs, with animation.
///
/// If `end` is lower than `start`, the parameters are swapped.
/// - Parameters:
///   - start: The position in base pairs that will correspond to the ``visibleOrigin`` of the view.
///   - end: The position in base pairs that will correspond to the right edge of the view's visible rectangle.
- (void)zoomFromSize:(float)start toSize:(float)end;

/// Zooms the view to the range of a marker label, with animation
///
/// This method assumes that the label` is among the ``LabelView/markerLabels`` that the view shows.
/// - Parameter label: The label whose range should occupy the whole visible width of the view.
- (void)zoomToMarkerLabel:(RegionLabel *)label;

/// Zooms the view to the range of its ``marker``, with animation.
///
/// This method does nothing if ``marker`` returns `nil`.
- (void)zoomToMarker;

/// Returns `YES` if the view has just had its size changed.
///
/// This property is used by ``TraceScrollView`` to avoid unwanted scrolling.
@property (nonatomic, readonly) BOOL isResizing;


# pragma mark - managing the vertical scale (height of curves)

/// The fluorescence level (in RFU) that corresponds to the top edge of the view.
///
/// This property determines the view's ``vScale`` and its setter sends `traceViewDidChangeTopFluoLevel` to the view's ``delegate``.
///
/// The effective value is constrained to the interval [20, 35000].
///
/// When given a new value for this property, the view sets it for the ``Trace/topFluoLevel`` of each trace among its ``loadedTraces`` and for its ``genotype``.
/// This allows other views to show this trace/genotype at the vertical scale that was set by the user, accounting for the fact that a trace/genotype may move between views in the reuse queue of an `NSTableView`.
@property (nonatomic) float topFluoLevel;

/// The vertical scale at which the view plots traces in points per fluorescence unit (RFU).
///
/// This property is computed from ``topFluoLevel`` and the height of the view.
@property (nonatomic, readonly) float vScale;

/// Sets the view's ``topFluoLevel`` without notifying its ``delegate``.
///
/// This can be used by the delegate to synchronize vertical scales between views without causing recursive notifications.
/// - Parameter fluo: The desired value for ``topFluoLevel``.
- (void)setTopFluoLevelAndDontNotify:(float)fluo;

/// Returns the desired ``topFluoLevel`` the view should have so that it scales to the highest visible peak in the given range.
///
/// The peaks considered are those from the view's ``loadedTraces``.
/// The fluorescence data to use is determined by ``showRawData``.
/// Peaks resulting from crosstalk are ignored if ``ignoreCrosstalkPeaks`` returns `YES`.
/// - Parameter range: The range in which peaks are evaluated.
- (float)topFluoForRange:(BaseRange)range;

/// Sets the vertical ``topFluoLevel`` of the view with animation.
///
/// - Parameters:
///   - fluo: The desired value for ``topFluoLevel``.
///   - animate: Whether to animation the change. If `YES`, this method  notifies the ``delegate`` of the change at every step of the animation.
- (void)setTopFluoLevel:(float)fluo withAnimation:(BOOL) animate;

/// Makes the trace view fit vertically in its superview.
///
/// This methods sets the view height so that its top edge reaches the bottom edge of its ``rulerView``.
///
/// This method change the view's ``vScale`` to maintain its ``topFluoLevel``,
/// i.e., the height of curves relative to the height of the view should not change.
- (void)fitVertically;
																		
/// Sets  the ``topFluoLevel`` of the view so that the highest visible peak among traces reaches top edge of the view.
///
/// This method uses ``topFluoForRange:`` and ``setTopFluoLevel:withAnimation:``.
/// - Parameter animate: Whether the change in vertical scale should be animated.
- (void)scaleToHighestPeakWithAnimation:(BOOL) animate;

# pragma mark - methods used for drawing

/// Returns the point, in the view coordinate system, corresponding to a given scan of the the view's ``trace``.
///
/// The returned value is the point composing the fluorescence curve representing the trace, for its fluorescence data at the `scan`.
/// If the scan is out or range and if the view shows no trace, the components of the point will be 0.
///
/// The fluorescence data used is determined by the ``showRawData`` property.
///
/// The `x`component of the point is determined by ``xForScan:``.
/// - Parameter scan: the scan for which the point should be returned.
- (CGPoint)pointForScan:(uint)scan;

/// Returns the horizontal location at which a data point (scan) of a trace should show in the view.
///
/// This method uses the ``LabelView/hScale`` and ``LabelView/sampleStartSize`` properties.
/// - Parameter scan: The scan for which the location should be returned.
- (CGFloat)xForScan:(uint)scan;

/// Returns a scan number (for the ``trace`` the view shows) at a horizontal position in the view coordinate system.
///
/// This method uses the ``LabelView/hScale`` and ``LabelView/sampleStartSize`` properties, as well as ``Chromatogram/scanForSize:``.
///
/// The returned value is not guaranteed to represent a fluorescence data point. This value can for instance be negative, depending on `position`.
/// - Parameter position: The position for which the scan should be returned.
- (int)scanForX:(float)position;



@end

NS_ASSUME_NONNULL_END
