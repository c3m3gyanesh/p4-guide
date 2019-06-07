// This program is hand-edited starting from the file:

// v1model-multiple-resubmit-reasons-resubmit-annot.p4

// It changes the annotations from @resubmit to @field_list, and uses
// names instead of integers to identify field lists, which is more
// similar to how it is done in P4_14.

#include <core.p4>
#include <v1model.p4>

// NEW: If a packet executes at least one resubmit(fl_name) operation
// while the ingress control is executed, let fl_name be the name
// given as the parameter of the last such resubmit() call.  For such
// packets, every user-defined metadata field with a
// @field_list(fl_name1, fl_name2, ...) will be preserved if fl_name
// is one of the names in the list of fl_names.

// Preserving a user-defined metadata field means that whatever value
// it has at the end of executing the ingress control block will be
// "saved" with the packet to be resubmitted, and when the resubmitted
// packet begins executing the ingress parser, all such preserved
// fields will be initialized to that saved value.

// Any field that is not preserved for a resubmitted packet will begin
// ingress parsing with its default value that it has for a new packet
// arriving on a switch port (see below for some questions on this topic).

// The field resubmit_reason has a list of 4 such names, since we want
// to preserve its value if a resubmit(fl_name) operation is done for
// any of those 4 names.

// Note that if a resubmit(fl_resubmit3) operation was the last one
// done during ingress, the values of f1, f2, and f4 should _not_ be
// preserved in the resubmitted packet, but instead those fields
// should be initialized to 0, as they would for a newly arriving
// packet from an input port.

// TBD: Should P4_16 + v1model architecture guarantee that
// user-defined metadata fields are initialized when the ingress
// parser begins, as the P4_14 specification says that such fields
// should always be initialized to 0?  I know that Vladimir Gurevich
// was arguing against this requirement in the P4_16 language
// specification itself, but perhaps making it a requirement of a
// particular architecture is not so onerous.

struct mymeta_t {
    @field_list(fl_resubmit1, fl_resubmit2, fl_resubmit3, fl_resubmit4) bit<3> resubmit_reason;
    @field_list(fl_resubmit1) bit<128> f1;
    @field_list(fl_resubmit2) bit<160> f2;
    @field_list(fl_resubmit3) bit<256> f3;
    @field_list(fl_resubmit4) bit<64>  f4;
}

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

struct metadata {
    mymeta_t mymeta;
}

struct headers {
    ethernet_t ethernet;
}

parser ParserImpl(packet_in packet,
    out headers hdr,
    inout metadata meta,
    inout standard_metadata_t standard_metadata)
{
    state start {
        transition parse_ethernet;
    }
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition accept;
    }
}

control egress(inout headers hdr,
    inout metadata meta,
    inout standard_metadata_t standard_metadata)
{
    apply {
    }
}

control ingress(inout headers hdr,
    inout metadata meta,
    inout standard_metadata_t standard_metadata)
{
    action set_port_to_mac_da_lsbs() {
        standard_metadata.egress_spec = (bit<9>) hdr.ethernet.dstAddr & 0xf;
    }
    action do_resubmit_reason1() {
        meta.mymeta.resubmit_reason = 1;
        meta.mymeta.f1 = meta.mymeta.f1 + 17;
        // NEW: resubmit() calls take a name, not a list of fields.
        // The _only_ effect this has is to immediately copy some
        // compiler-generated integer (one chosen by the compiler to
        // represent the name that is the argument) into a per-packet
        // hidden field.  In the current BMv2 simple_switch
        // implementation, this field isn't even hidden -- it is field
        // 'resubmit_flag' in the standard metadata structure.

        // This integer value will be used later when ingress
        // processing is complete, by the architecture, to select
        // which user-defined metadata fields to preserve in the
        // resubmitted packet.
        resubmit(fl_resubmit1);
    }
    action do_resubmit_reason2(bit<160> f2_val) {
        meta.mymeta.resubmit_reason = 2;
        meta.mymeta.f2 = f2_val;
        // NEW: resubmit() calls take a name
        resubmit(resubmit_fl2);
    }
    action nop() {
    }
    action my_drop() {
        mark_to_drop(standard_metadata);
    }
    action do_resubmit_reason3() {
        meta.mymeta.resubmit_reason = 3;
        meta.mymeta.f3 = (bit<256>) hdr.ethernet.srcAddr;
        meta.mymeta.f3 = meta.mymeta.f3 + (bit<256>) hdr.ethernet.dstAddr;
        // NEW: resubmit() calls take a name
        resubmit(resubmit_fl3);
    }
    action do_resubmit_reason4() {
        meta.mymeta.resubmit_reason = 4;
        meta.mymeta.f4 = (bit<64>) hdr.ethernet.etherType;
        // NEW: resubmit() calls take a name
        resubmit(resubmit_fl4);
    }
    action update_metadata(bit<64> x) {
        meta.mymeta.f1 = meta.mymeta.f1 - 2;
        meta.mymeta.f2 = 8;
        meta.mymeta.f3 = (bit<256>) hdr.ethernet.etherType;
        meta.mymeta.f4 = meta.mymeta.f4 + x;
    }
    table t_first_pass_t1 {
        actions = {
            set_port_to_mac_da_lsbs;
            do_resubmit_reason1;
            do_resubmit_reason2;
            @defaultonly nop;
        }
        key = {
            hdr.ethernet.srcAddr: ternary;
        }
        default_action = nop();
    }
    table t_first_pass_t2 {
        actions = {
            my_drop;
            do_resubmit_reason3;
            do_resubmit_reason4;
        }
        key = {
            hdr.ethernet.dstAddr: ternary;
        }
        default_action = my_drop();
    }
    table t_first_pass_t3 {
        actions = {
            update_metadata;
            @defaultonly nop;
        }
        key = {
            hdr.ethernet.etherType: ternary;
        }
        default_action = nop();
    }
    table t_second_pass_reason1 {
        actions = {
            my_drop;
            nop;
            set_port_to_mac_da_lsbs;
        }
        key = {
            meta.mymeta.f1: exact;
        }
        default_action = nop();
    }
    table t_second_pass_reason2 {
        actions = {
            nop;
            do_resubmit_reason1;
        }
        key = {
            meta.mymeta.f2: ternary;
        }
        default_action = nop();
    }
    table t_second_pass_reason3 {
        actions = {
            my_drop;
            set_port_to_mac_da_lsbs;
            @defaultonly nop;
        }
        key = {
            meta.mymeta.f3        : exact;
            hdr.ethernet.etherType: exact;
        }
        default_action = nop();
    }
    table t_second_pass_reason4 {
        actions = {
            my_drop;
            nop;
            set_port_to_mac_da_lsbs;
        }
        key = {
            meta.mymeta.f4      : ternary;
            hdr.ethernet.srcAddr: exact;
        }
        default_action = nop();
    }
    apply {
        if (meta.mymeta.resubmit_reason == 0) {
            // This is a new packet, not a resubmitted one
            t_first_pass_t1.apply();
            // Note that even if a resubmit() call was performed while
            // executing an action for table t_first_pass_t1, we may
            // do another resubmit() call while executing an action
            // for table t_first_pass_t2.  In general, the last
            // resubmit() call should have its field list preserved.
            // Each resubmit() call causes any earlier resubmit()
            // calls made during the same execution of the ingress
            // control to be "forgotten".
            t_first_pass_t2.apply();
            // Since in this imagined version of the program, we are
            // only passing integer id values to the resubmit() calls,
            // and waiting until the end of the ingress control to
            // actually preserve the desired list of fields, we are
            // not introducing new P4_16 language semantics in order
            // to preserve those final values of the fields.
            
            // recirculate and clone operations, and perhaps also
            // digest calls (TBD what their "timing" is for copying
            // the field values is relative to the call to
            // generate_digest() in P4_14), should be handled
            // similarly in P4_16, in order to match their P4_14
            // behavior.
            t_first_pass_t3.apply();
        }
        else if (meta.mymeta.resubmit_reason == 1) {
            t_second_pass_reason1.apply();
        } else if (meta.mymeta.resubmit_reason == 2) {
            t_second_pass_reason2.apply();
        } else if (meta.mymeta.resubmit_reason == 3) {
            t_second_pass_reason3.apply();
        } else {
            t_second_pass_reason4.apply();
        }
    }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
    }
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply {
    }
}

V1Switch(ParserImpl(), verifyChecksum(), ingress(),
    egress(), computeChecksum(), DeparserImpl()) main;

