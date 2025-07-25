// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
#ifndef PINS_TEST_GNMI_BLACKHOLE_CONGESTION_COUNTERS_IXIA_TEST_H_
#define PINS_TEST_GNMI_BLACKHOLE_CONGESTION_COUNTERS_IXIA_TEST_H_

#include <cstdint>
#include <memory>
#include <vector>

#include "absl/status/statusor.h"
#include "lib/utils/generic_testbed_utils.h"
#include "proto/gnmi/gnmi.grpc.pb.h"
#include "thinkit/generic_testbed.h"
#include "thinkit/generic_testbed_fixture.h"

namespace pins_test {

struct InErrorCounters {
  uint64_t port_in_error_packets;
  uint64_t port_blackhole_in_error_events;
  uint64_t switch_blackhole_in_error_events;
  uint64_t switch_blackhole_events;
};

class BlackholeCongestionCountersIxiaTestFixture
    : public thinkit::GenericTestbedFixture<> {
 protected:
  // Acquires testbed with 3 pairs of connected ports between SUT and Ixia.
  void SetUp() override;
  absl::StatusOr<InErrorCounters> TriggerInFcsErrors(int frame_rate_per_second,
                                                     int frame_count);
  std::unique_ptr<thinkit::GenericTestbed> generic_testbed_;
  std::unique_ptr<gnmi::gNMI::StubInterface> gnmi_stub_;
  std::vector<InterfaceLink> traffic_generator_links_;
};

}  // namespace pins_test

#endif  // PINS_TEST_GNMI_BLACKHOLE_CONGESTION_COUNTERS_IXIA_TEST_H_
