import type { SingleProfileData } from "./singleHelpers";

/// Shared by discovery and the interest transaction. The second check is essential: a profile
/// can change between the moment it was suggested and the moment someone taps "Interesse".
export function isMutuallyCompatible(own: SingleProfileData, candidate: SingleProfileData): boolean {
  const cityMatches = own.cityNormalized === candidate.cityNormalized;
  const ownAcceptsCandidate = candidate.age >= own.preferredAgeMinimum && candidate.age <= own.preferredAgeMaximum;
  const candidateAcceptsOwn = own.age >= candidate.preferredAgeMinimum && own.age <= candidate.preferredAgeMaximum;
  return cityMatches && ownAcceptsCandidate && candidateAcceptsOwn;
}
