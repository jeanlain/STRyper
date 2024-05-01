//
//  FragmentLabel.h
//  STRyper
//
//  Created by Jean Peccoud on 02/11/12.
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


#import "ViewLabel.h"

@class LadderFragment, PeakLabel;


/// A  draggable label that indicates the size or name of a DNA fragment (ladder fragment or allele) on a trace view.
///
/// A fragment label represents a ``LadderFragment`` entity, which can be an ``Allele``.
///
/// This label shows a rectangular text box that indicates the ``LadderFragment/size`` of the fragment or its ``LadderFragment/name`` if the fragment is an ``Allele``.
@interface FragmentLabel : ViewLabel <NSControlTextEditingDelegate, NSTextFieldDelegate>

/// Returns a label that is initialized given a fragment.
///
/// The method does not check if the `fragment` is among the ``Trace/fragments`` of the ``TraceView/trace`` the `view` shows.
/// - Parameters:
///   - fragment: The fragment that the label will represent.
///   - view: The view on which the label will show.
- (instancetype)initFromFragment:(LadderFragment*)fragment view:(TraceView *)view NS_DESIGNATED_INITIALIZER;

/// The allele or ladder fragment that the label represents.
///
/// ``ViewLabel/representedObject`` also returns this object.
@property (nonatomic) __kindof LadderFragment *fragment;

/// Repositions the ``TraceView/fragmentLabels`` of a ``TraceView`` to avoid collisions.
///
/// This method is assumed to be called after all fragment labels of the `view` have been repositioned.
/// It moves labels vertically, never horizontally.
/// - Parameters:
///   - view: The view in which labels should be repositioned.
///   - animate: Whether labels are repositioned with animation.
+(void) avoidCollisionsInView:(TraceView *)view allowAnimation:(BOOL)animate;

/**************** implementations of methods defined in the superclass *****************/

/// Returns `NO`.
///
/// The label does not get ``ViewLabel/hovered`` and does not generate a ``ViewLabel/trackingArea``.
- (BOOL)tracksMouse;

/// Implements the ``ViewLabel/reposition`` method.
///
/// When not ``ViewLabel/dragged``, the label positioned itself slightly above the fluorescence curve at the location of its ``fragment`` in base pairs.
/// If the fragment  has a ``LadderFragment/scan`` ≤ 0 and is a ladder fragment, the label places itself against the top edge of its ``ViewLabel/view``, at a horizontal position corresponding to the fragment's ``LadderFragment/size``.
///
/// If the fragment is an allele and has a scan ≤ 0 (i.e., it is a missing allele), the label positions itself beyond the top edge of the view, at a position corresponding to the midpoint of the ``Genotype/marker``.
- (void)reposition;

/// Implements the ``ViewLabel/drag`` method.
///
/// The method automatically repositions the label according to the ``LabelView/mouseLocation``.
/// If the label is dragged close to a peak that is a suitable destination (which the method determines),
/// the peak label takes its ``ViewLabel/hovered`` state and some magnetism locks the horizontal position of the dragged label, with haptic feedback.
///
/// If the label is dragged above the top edge of the view, it stops moving and pops  a `disappearingItemCursor` .
///
/// At the end of dragging, the ``fragment`` represented by the dragged label will take its ``LadderFragment/scan`` from the destination peak at the end of the dragging session.
/// For an label representing an ``Allele``,  the ``fragment`` will also get the name of the ``Bin`` comprising the new peak, if any.
/// If the label was dragged above the top edge of the view, it calls its ``deleteAction:``.
///
/// See the ``STRyper`` user guide for more information.
- (void)drag;

/// Implements the ``ViewLabel/doubleClickAction:``method.
///
/// If the label represents an  ``Allele``,  the method spawns a text field over the label, allowing the user to change the allele ``LadderFragment/name``.
///
/// If the label represents an  ladder fragment,  the method removes the fragment from sizing.
/// - Parameter sender: The object that send the message. It is ignored by the method.
- (void)doubleClickAction:(id)sender;

/// Implements the ``ViewLabel/deleteAction:`` method.
/// 
/// If the label represents an ladder fragment, the method removes the fragment from sizing.
///
/// If the label represents a non-additional allele, the allele takes a scan of 0 (see ``Allele`` class for the consequences).
/// If the label is additional, it is deleted and the receiver removed from its ``ViewLabel/view``.
- (void)deleteAction:(id)sender;

@end
