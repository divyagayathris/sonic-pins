#ifndef SAI_PACKET_REWRITES_P4_
#define SAI_PACKET_REWRITES_P4_

#include <v1model.p4>
#include "headers.p4"
#include "metadata.p4"
#include "minimum_guaranteed_sizes.h"
#include "bmv2_intrinsics.h"
#include "ids.h"

// To be applied only for multicast-replicated packets, i.e. packets with
// `standard_metadata.instance_type == PKT_INSTANCE_TYPE_REPLICATION`.
// In P4Runtime, these are packets created by a `Replica` of a
// `MulticastGroupEntry`.
control multicast_rewrites(inout local_metadata_t local_metadata,
                           in standard_metadata_t standard_metadata) {
  // The egress port of the multicast-replicated packet.
  // In P4Runtime, equal to the `port` value of the `Replica` of the
  // `MulticastGroupEntry` that created this packet.
  port_id_t multicast_replica_port = (port_id_t) standard_metadata.egress_port;

  // The instance number of the multicast-replicated packet.
  // In P4Runtime, equal to the `instance` value of the `Replica` of the
  // `MulticastGroupEntry` that created this packet.
  replica_instance_t multicast_replica_instance =
      standard_metadata.egress_rid;

  @id(ROUTING_SET_MULTICAST_SRC_MAC_ACTION_ID)
  action set_multicast_src_mac(@id(1) @format(MAC_ADDRESS)
                               ethernet_addr_t src_mac) {
    local_metadata.enable_src_mac_rewrite = true;
    local_metadata.packet_rewrites.src_mac = src_mac;

    // By default VLAN is removed (if present). This is modeled by rewriting
    // vlan_id to the INTERNAL_VLAN_ID.
    local_metadata.enable_vlan_rewrite = true;
    local_metadata.packet_rewrites.vlan_id = INTERNAL_VLAN_ID;
  }

  @id(ROUTING_IP_MULTICAST_SET_SRC_MAC_AND_VLAN_ID_ACTION_ID)
  @action_restriction("
    // Disallow reserved VLAN IDs with implementation-defined semantics.
    vlan_id != 0 && vlan_id != 4095")
  action multicast_set_src_mac_and_vlan_id(
      @id(1) @format(MAC_ADDRESS) ethernet_addr_t src_mac,
      @id(2) vlan_id_t vlan_id) {
    local_metadata.enable_src_mac_rewrite = true;
    local_metadata.packet_rewrites.src_mac = src_mac;

    local_metadata.enable_vlan_rewrite = true;
    local_metadata.packet_rewrites.vlan_id = vlan_id;
  }

  @id(ROUTING_IP_MULTICAST_SET_SRC_MAC_ACTION_ID)
  action multicast_set_src_mac(@id(1) @format(MAC_ADDRESS)
                               ethernet_addr_t src_mac) {
    multicast_set_src_mac_and_vlan_id(src_mac, INTERNAL_VLAN_ID);
  }

  @id(ROUTING_IP_MULTICAST_SET_SRC_MAC_AND_DST_MAC_AND_VLAN_ID_ACTION_ID)
  @action_restriction("
    // Disallow reserved VLAN IDs with implementation-defined semantics.
    vlan_id != 0 && vlan_id != 4095")
  action multicast_set_src_mac_and_dst_mac_and_vlan_id(
      @id(1) @format(MAC_ADDRESS) ethernet_addr_t src_mac,
      @id(2) @format(MAC_ADDRESS) ethernet_addr_t dst_mac,
      @id(3) vlan_id_t vlan_id) {
    local_metadata.enable_src_mac_rewrite = true;
    local_metadata.packet_rewrites.src_mac = src_mac;

    local_metadata.enable_dst_mac_rewrite = true;
    local_metadata.packet_rewrites.dst_mac = dst_mac;

    local_metadata.enable_vlan_rewrite = true;
    local_metadata.packet_rewrites.vlan_id = vlan_id;
  }

  @id(ROUTING_IP_MULTICAST_SET_SRC_MAC_AND_PRESERVE_INGRESS_VLAN_ID_ACTION_ID)
  action multicast_set_src_mac_and_preserve_ingress_vlan_id(
      @id(1) @format(MAC_ADDRESS) ethernet_addr_t src_mac) {
    local_metadata.enable_src_mac_rewrite = true;
    local_metadata.packet_rewrites.src_mac = src_mac;

    local_metadata.enable_vlan_rewrite = false;
  }

  @id(ROUTING_L2_MULTICAST_PASSTHROUGH_ACTION_ID)
  action l2_multicast_passthrough() {}

  // This is a logical table that does not exist in SAI and instead is managed
  // by the Orchagent. It is used to distinguish between L2 and IP
  // multicast-replicated packets.
  //  * L2MC packets will use the l2_multicast_passthrough action
  //  * IPMC packets will use set_multicast_src_mac action.
  //
  // L2MC packets will not be modified in any way and simply duplicated to
  // various output ports. IP packets will rewrite the source MAC.
  //
  // For IPMC there is a many-to-one correspondence between entries in this
  // table and SAI Router Interfaces (RIFs). Each entry corresponds to a RIF
  // with the following attributes:
  // * `SAI_ROUTER_INTERFACE_ATTR_PORT_ID` is equal to `multicast_replica_port`.
  // * `SAI_ROUTER_INTERFACE_ATTR_SRC_MAC_ADDRESS` is equal to the `src_mac`
  //   parameter of the `set_multicast_src_mac` action.
  //
  // Orchagent maintains a mapping from entries to RIFs, creating and destroying
  // (possibly shared) RIFs as entries are inserted and deleted.
  //
  // When creating a multicast group member (`SAI_IPMC_GROUP_MEMBER`) from a
  // P4Runtime `Replica`, Orchagent will use this table to set the value of the
  // `SAI_IPMC_GROUP_MEMBER_ATTR_IPMC_OUTPUT_ID` attribute: it will expect to
  // find an entry for the replica's port and instance in this table, and will
  // use the ID of the RIF associated with that entry. This will cause the
  // source MAC of packets generated by the group member to be rewritten to the
  // `src_mac` of the `set_multicast_src_mac` action of the entry.
  @p4runtime_role(P4RUNTIME_ROLE_ROUTING)
  @id(ROUTING_MULTICAST_ROUTER_INTERFACE_TABLE_ID)
  table multicast_router_interface_table {
    key = {
      multicast_replica_port : exact
        @referenced_by(builtin::multicast_group_table, replica.port)
        @id(1);
      multicast_replica_instance : exact
        @referenced_by(builtin::multicast_group_table, replica.instance)
        @id(2);
    }
    actions = {
      // TODO: Remove once no longer in use.
      // Deprecated: use `set_src_mac` instead.
      @proto_id(1) set_multicast_src_mac;
      @proto_id(2) l2_multicast_passthrough;
      @proto_id(3) multicast_set_src_mac;
      @proto_id(4) multicast_set_src_mac_and_vlan_id;
      @proto_id(5) multicast_set_src_mac_and_dst_mac_and_vlan_id;
      @proto_id(6) multicast_set_src_mac_and_preserve_ingress_vlan_id;
    }
    size = ROUTING_MULTICAST_SOURCE_MAC_TABLE_MINIMUM_GUARANTEED_SIZE;
  }

  apply {
    multicast_router_interface_table.apply();
  }
}  // control multicast_rewrites

control ttl_logic(inout headers_t headers,
                   in local_metadata_t local_metadata,
                   inout standard_metadata_t standard_metadata) {
  apply {
    bool acl_l3_redirect =
          (local_metadata.acl_ingress_ipmc_redirect ||
          local_metadata.acl_ingress_nexthop_redirect);

    // IPv4 TTL check.
    if (headers.ipv4.isValid()) {
      // Remove when switch correctly accepts TTL=1 packets.
      if (headers.ipv4.ttl == 1 && !acl_l3_redirect) {
          mark_to_drop(standard_metadata);
      }

      // Remove this clause and only decrement on TTL>0
      // below when redirect to nexthop behavior correctly drops packets
      // ingressing with TTL == 0.
      if (headers.ipv4.ttl == 0 && !local_metadata.acl_ingress_nexthop_redirect) {
          mark_to_drop(standard_metadata);
      }

      if (local_metadata.enable_decrement_ttl) {
        // Note that this TTL can purposefully overflow when
        // TTL == 0. The guard should be updated to preclude that when it is no
        // longer the case.
        headers.ipv4.ttl = headers.ipv4.ttl - 1;
      }

      // Remove ACL redirect check when redirection
      // correctly drops TTL=0 packets.
      // Note: This line is currently redundant, but will be needed when the
      // bugs above are fixed and their related lines removed.
      if (headers.ipv4.ttl == 0 && !acl_l3_redirect) {
          mark_to_drop(standard_metadata);
      }
    }

    // IPv6 TTL (aka hop limit) check.
    if (headers.ipv6.isValid()) {
      // Remove when switch correctly accepts TTL=1 packets.
      if (headers.ipv6.hop_limit == 1 && !acl_l3_redirect) {
          mark_to_drop(standard_metadata);
      }

      // Remove this clause and only decrement on TTL>0
      // below when redirect to nexthop behavior correctly drops packets
      // ingressing with TTL == 0.
      if (headers.ipv6.hop_limit == 0 &&
          !local_metadata.acl_ingress_nexthop_redirect) {
          mark_to_drop(standard_metadata);
      }

      if (local_metadata.enable_decrement_ttl) {
        // Note that this TTL can purposefully overflow when
        // TTL == 0. The guard should be updated to preclude that when it is no
        // longer the case.
        headers.ipv6.hop_limit = headers.ipv6.hop_limit - 1;
      }

      // Remove ACL redirect check when redirection
      // correctly drops TTL=0 packets.
      // Note: This line is currently redundant, but will be needed when the
      // bugs above are fixed and their related lines removed.
      if (headers.ipv6.hop_limit == 0 && !acl_l3_redirect) {
          mark_to_drop(standard_metadata);
      }
    }
  }
} // control ttl_logic

// This control block applies the rewrites computed during the ingress
// stage to the actual packet.
control packet_rewrites(inout headers_t headers,
                        inout local_metadata_t local_metadata,
                        inout standard_metadata_t standard_metadata) {
  apply {
    if (standard_metadata.instance_type == PKT_INSTANCE_TYPE_REPLICATION) {
      local_metadata.enable_decrement_ttl = true;
      multicast_rewrites.apply(local_metadata, standard_metadata);
    }
    if (local_metadata.enable_src_mac_rewrite) {
      headers.ethernet.src_addr = local_metadata.packet_rewrites.src_mac;
    }
    if (local_metadata.enable_dst_mac_rewrite) {
      headers.ethernet.dst_addr = local_metadata.packet_rewrites.dst_mac;
    }
    if (local_metadata.enable_vlan_rewrite) {
      // VLAN id is kept in local_metadata until the end of egress pipeline
      // where depending on the value of VLAN id and VLAN configuration the
      // packet might potentially get VLAN tagged with that VLAN id.
      local_metadata.vlan_id = local_metadata.packet_rewrites.vlan_id;
    }
    if (local_metadata.enable_dscp_rewrite) {
      if (headers.ipv4.isValid()) {
        headers.ipv4.dscp = local_metadata.packet_rewrites.dscp;
      }
      if (headers.ipv6.isValid()) {
        headers.ipv6.dscp = local_metadata.packet_rewrites.dscp;
      }
    }
    // Perform TTL logic after all other packet rewrites have been applied.
    ttl_logic.apply(headers, local_metadata, standard_metadata);
  }
}  // control packet_rewrites

#endif  // SAI_PACKET_REWRITES_P4_
