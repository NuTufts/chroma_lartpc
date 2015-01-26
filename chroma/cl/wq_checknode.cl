//-*-c-*-
#include "geometry_types.h"
#include "wq_intersect_bvh.h"

__kernel void checknode( const int max_loops, 
			 // Photon info [index by photon id]
			 __global float3 *positions, __global float3 *directions, __global uint* current_node, __global uint* test_node,
			 // Geometry    [indexed by node id]
			 __global uint4* nodes, __global uint* node_parent, __global uint* node_first_daughter, __global uint* node_sibling, __global uint* node_aunt,
			 const float3 world_origin, const float world_scale,
			 // work queue  [indexed slot]
			 const int queue_size, __global int* queue_photon_index, __global int* queue_slot_flag, 
			 // workgroup variables [indexed by local id]
			 const int workgroup_size, __local int* workgroup_photons, __local int* workgroup_current_node, __local int* workgroup_tested_node,
			 const int max_nodes_can_store, __local uint4* workgroup_nodes, const int loaded_node_start_index, const int loaded_node_end_index
			 ) {
  int localid = get_local_id(0);
  int groupid = get_group_id(0);

  __local uint pop_pos;
  __local uint push_pos;
  __local uint nodefront_min_index;
  __local uint nodefront_max_index;
  __local uint requestnode_min;
  __local uint requestnode_max;
  __local bool transfer_nodes;
  __local uint iloop;

  // initialize local variables
  if ( get_local_id(0) == 0) {
    pop_pos = 0;
    push_pos = workgroup_size;
    nodefront_min_index = loaded_node_start_index;
    nodefront_max_index = loaded_node_end_index;
    requestnode_min = 0;
    requestnode_max = 1;
    iloop = 0;
  }
  barrier( CLK_LOCAL_MEM_FENCE );

  // WORK QUEUE LOOP STARTS HERE
  int thread_iloop = iloop;

  while (thread_iloop<max_loops) {

    // all work items load requested photon and node
    int queue_index = pop_pos + localid;

    if ( queue_index < queue_size && queue_slot_flag[queue_index]==1 ) {
      atomic_xchg( queue_slot_flag + queue_index,  0); // pop this slot
      workgroup_photons[ localid ]       = queue_photon_index[ queue_index ]; // queue needs to be filled by cpu before launching kernel
      workgroup_current_node[ localid ]  = current_node[ workgroup_photons[ queue_index ] ];
      workgroup_tested_node[ localid ]   = test_node[ workgroup_photons[ queue_index ] ];
    }
    else {
      workgroup_photons[ localid ] = -1;
      workgroup_current_node[ localid ] = -1;
      workgroup_tested_node[ localid ] = -1;
    }


    if ( get_local_id(0) == 0) {
      int next_pos = pop_pos + (uint)workgroup_size;
      transfer_nodes = false;
      // move queue position
      if ( next_pos >= queue_size ) 
	next_pos = 0;
      pop_pos = next_pos;
    }

    // thread zero, 
    
    barrier( CLK_LOCAL_MEM_FENCE );

    // thread zero, polls range of nodes to get
    if ( get_local_id(0) == 0) {
      for (int i=0; i<workgroup_size; i++) {
	if ( workgroup_photons[ i ]>=0 ) { // we ignore non-filled threads
	  requestnode_min = min( requestnode_min, (uint)workgroup_current_node[ i ] );
	  requestnode_max = max( requestnode_max, (uint)workgroup_tested_node[ i ] );
	}
      }

      // easy scenario, we can fit all requested nodes (or more) into shared memory
      if ( (requestnode_max-requestnode_min)<=(uint)max_nodes_can_store ) {
	requestnode_max = requestnode_min+max_nodes_can_store;
	// if we don't have the nodes we need, schedule a transfer, update the front
	if ( requestnode_min<nodefront_min_index || requestnode_max>nodefront_max_index ) {
	  transfer_nodes = true;
	  nodefront_min_index = requestnode_min;
	  nodefront_max_index = requestnode_max;
	}
      }
      else {
	// hard scenario, we can't load them all in. we accomodate as many as we can this pass.
	// just not ready yet
	//printf('cannot aad nodes\n');
	current_node[ localid ] = requestnode_max-requestnode_min;      
	return;
      }
    }

    // workgroup works together to load nodes into local memory
    int nodefront_min = nodefront_min_index;
    int nodefront_max = nodefront_max_index;
    barrier( CLK_LOCAL_MEM_FENCE );
    
    if ( transfer_nodes ) {
      for (int iblock=0; nodefront_min + iblock*workgroup_size <nodefront_max; iblock++ ) {
	int inode = iblock*workgroup_size + localid;
	if ( inode < max_nodes_can_store )
	  workgroup_nodes[ inode ] = nodes[ nodefront_min + iblock*workgroup_size + localid ];
      }
    }
    barrier( CLK_LOCAL_MEM_FENCE );

    // -- Now we finally get to testing intersections --
    
    if ( workgroup_photons[ localid ]>=0 ) { // we ignore non-filled threads

/*       // get photon information */
      float3 photon_pos = positions[ workgroup_photons[ localid ] ];  // global access
      float3 photon_dir = directions[ workgroup_photons[ localid ] ]; // global access
      uint local_test_nodeid    = workgroup_tested_node[ localid ]  - nodefront_min_index; // zero index
      uint local_current_nodeid = workgroup_current_node[ localid ] - nodefront_min_index; // zero index
      
/*       // get and unpack node */
/*       Node node_struct; */
/*       uint4 workitem_node = workgroup_nodes[localid]; */
/*       //uint4 workitem_node = workgroup_nodes[ local_test_nodeid ]; // get the tested node */
/*       //uint4 workitem_node_current = workgroup_nodes[ workgroup_current_node[localid] ]; // get the current node */
/*       uint3 lower_int = (uint3)(workitem_node.x & 0xFFFF, workitem_node.y & 0xFFFF, workitem_node.z & 0xFFFF); */
/*       uint3 upper_int = (uint3)(workitem_node.x >> 16, workitem_node.y >> 16, workitem_node.z >> 16); */
/*       int get_aligned_axis( const float3 *direction ); */
/*       float3 flower = (float3) ( lower_int.x, lower_int.y, lower_int.z ); */
/*       float3 fupper = (float3) ( upper_int.x, upper_int.y, upper_int.z ); */
/*       node_struct.lower = world_origin + flower * world_scale; */
/*       node_struct.upper = world_origin + fupper * world_scale; */
/*       node_struct.child = workitem_node.w & ~NCHILD_MASK; */
/*       node_struct.nchild = workitem_node.w >> CHILD_BITS; */

/*       int intersects = intersect_internal_node( &photon_pos, &photon_dir, &node_struct ); */

      // assume it intersects, update photon queue
      current_node[ workgroup_photons[ localid ]  ] = workgroup_tested_node[ localid ];
      //current_node[ workgroup_photons[ localid ]  ] = workitem_node.w;
      //current_node[ workgroup_photons[ localid ]  ] = local_test_nodeid;
    }
    
    if ( localid==0 ) {
      iloop += 1;
    }
    barrier( CLK_LOCAL_MEM_FENCE );
    thread_iloop = iloop;
/*     if (  workgroup_photons[ localid ]>=0 ) { */
/*       current_node[ workgroup_photons[ localid ]  ] = thread_iloop; */
/*     } */
    barrier( CLK_LOCAL_MEM_FENCE );
  }

  return;

}
