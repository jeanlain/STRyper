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


/// A  draggable label that indicates the size or name of a DNA fragment (ladder fragment or allele) on a view.
///
///	A fragment label represents a ``LadderFragment`` entity, which can be an ``Allele``.
///
///	This label shows a rectangular text box above the peak corresponding to the ``fragment``, on the fluorescence curve drawn by a ``TraceView``.
///	The box text indicates the ``LadderFragment/size`` of the fragment or its ``LadderFragment/name`` if the fragment is an ``Allele``.
/// This box resides on the label's ``ViewLabel/layer``.
///
/// This class overrides the ``ViewLabel/drag`` method to allow the user to move the label to a new peak, if this peak is represented by a ``PeakLabel`` object on the ``ViewLabel/view``.
///
/// The ``fragment`` represented by the moved label will take its ``LadderFragment/scan`` from this new peak.
/// For an label representing an ``Allele``,  the ``fragment`` will also get the name of the ``Bin`` comprising the new peak, if there is any.
/// See the ``STRyper`` user guide for more information on the consequences of these actions.
///
/// **Positioning:** if the fragment that the label represents has a ``LadderFragment/scan`` ≤ 0 and is a ladder fragment, the label places itself against the top edge of its ``ViewLabel/view``, at a horizontal position corresponding to the fragment's ``LadderFragment/size``.
///
/// If the fragment is an allele and has a scan ≤ 0 (i.e., it is a missing allele), the label positions itself beyond the top edge of the view, at a position corresponding to the midpoint of the ``Genotype/marker``.
///
/// If the label represents an  allele, the ``ViewLabel/doubleClickAction:`` message spawns a text field over the label, allowing the user to change the allele ``LadderFragment/name``.
///
/// The ``ViewLabel/deleteAction:`` message removes a ladder size or an allele from the peak at the label.
@interface FragmentLabel : ViewLabel <NSControlTextEditingDelegate>

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
@property (weak, readonly) LadderFragment *fragment;



/// Internal property used to avoid collision with other labels.
///
/// This is used internally and should not be set by other classes
@property (nonatomic) float _distanceToMove;


@end
