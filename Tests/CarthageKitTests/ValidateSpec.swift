@testable import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Result
import Tentacle

private extension CarthageError {
	var compatibilityInfos: [CompatibilityInfo] {
		if case let .invalidResolvedCartfile(infos) = self {
			return infos
		}
		return []
	}
}

class ValidateSpec: QuickSpec {
	override func spec() {
		let validCartfile = """
					github "Alamofire/Alamofire" "4.6.0"
					github "CocoaLumberjack/CocoaLumberjack" "3.4.1"
					github "Moya/Moya" "10.0.2"
					github "ReactiveCocoa/ReactiveSwift" "2.0.1"
					github "ReactiveX/RxSwift" "4.1.2"
					github "antitypical/Result" "3.2.4"
					github "yapstudios/YapDatabase" "3.0.2"
					"""

		let invalidCartfile = """
					github "Alamofire/Alamofire" "5.0.0"
					github "CocoaLumberjack/CocoaLumberjack" "gitcommit"
					github "Moya/Moya" "10.0.2"
					github "ReactiveCocoa/ReactiveSwift" "2.0.1"
					github "ReactiveX/RxSwift" "4.1.2"
					github "antitypical/Result" "4.0.0"
					github "yapstudios/YapDatabase" "3.0.2"
					"""

		let moyaDependency = Dependency.gitHub(.dotCom, Repository(owner: "Moya", name: "Moya"))
		let resultDependency = Dependency.gitHub(.dotCom, Repository(owner: "antitypical", name: "Result"))
		let alamofireDependency = Dependency.gitHub(.dotCom, Repository(owner: "Alamofire", name: "Alamofire"))
		let reactiveSwiftDependency = Dependency.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveSwift"))
		let rxSwiftDependency = Dependency.gitHub(.dotCom, Repository(owner: "ReactiveX", name: "RxSwift"))
		let yapDatabaseDependency = Dependency.gitHub(.dotCom, Repository(owner: "yapstudios", name: "YapDatabase"))
		let cocoaLumberjackDependency = Dependency.gitHub(.dotCom, Repository(owner: "CocoaLumberjack", name: "CocoaLumberjack"))
		
		describe("requirementsByDependency") {
			it("should group dependencies by parent dependency") {
				let resolvedCartfile = ResolvedCartfile.from(string: validCartfile)
				let project = Project(directoryURL: URL(string: "file://fake")!)
				
				let result = project.requirementsByDependency(resolvedCartfile: resolvedCartfile.value!, tryCheckoutDirectory: false).single()
				
				expect(result?.value?.count) == 3
				
				expect(Set(result?.value?[moyaDependency]?.map { $0.0 } ?? [])) ==
					   Set([resultDependency, alamofireDependency, reactiveSwiftDependency, rxSwiftDependency])
				
				expect(Set(result?.value?[reactiveSwiftDependency]?.map { $0.0 } ?? [])) == Set([resultDependency])
				
				expect(Set(result?.value?[yapDatabaseDependency]?.map { $0.0 } ?? [])) == Set([cocoaLumberjackDependency])
			}
		}
		
		describe("validate") {
			it("should identify a valid Cartfile.resolved as compatible") {
				let resolvedCartfile = ResolvedCartfile.from(string: validCartfile)
				let project = Project(directoryURL: URL(string: "file://fake")!)
				
				let result = project.validate(resolvedCartfile: resolvedCartfile.value!).single()
				
				expect(result?.value).notTo(beNil())
			}
			
			it("should identify incompatibilities in an invalid Cartfile.resolved") {
				// These tuples represent the desired version of a dependency, paired with its parent dependency;
				// moya_3_1_0 indicates that Moya expects a version compatible with 3.1.0 of *another* dependency
				let moya_3_1_0 = (moyaDependency, VersionSpecifier.compatibleWith(SemanticVersion(major: 3, minor: 1, patch: 0)))
				let moya_4_1_0 = (moyaDependency, VersionSpecifier.compatibleWith(SemanticVersion(major: 4, minor: 1, patch: 0)))
				let reactiveSwift_3_2_1 = (reactiveSwiftDependency, VersionSpecifier.compatibleWith(SemanticVersion(major: 3, minor: 2, patch: 1)))
				
				let resolvedCartfile = ResolvedCartfile.from(string: invalidCartfile)
				let project = Project(directoryURL: URL(string: "file://fake")!)
				
				let error = project.validate(resolvedCartfile: resolvedCartfile.value!).single()?.error
				let infos = error?.compatibilityInfos
				
				expect(infos?[0].dependency) == alamofireDependency
				expect(infos?[0].pinnedVersion) == PinnedVersion("5.0.0")
				
				expect(infos?[0].incompatibleRequirements.contains(where: { $0 == moya_4_1_0 })) == true
				
				expect(infos?[1].dependency) == resultDependency
				expect(infos?[1].pinnedVersion) == PinnedVersion("4.0.0")
				
				expect(infos?[1].incompatibleRequirements.contains(where: { $0 == moya_3_1_0 })) == true
				expect(infos?[1].incompatibleRequirements.contains(where: { $0 == reactiveSwift_3_2_1 })) == true

				expect(error?.description) ==
					"""
					The following incompatibilities were found in Cartfile.resolved:
					* Alamofire "5.0.0" is incompatible with Moya ~> 4.1.0
					* Result "4.0.0" is incompatible with Moya ~> 3.1.0
					* Result "4.0.0" is incompatible with ReactiveSwift ~> 3.2.1
					"""
			}
		}

		describe("invert requirements") {
			it("should correctly invert a requirements dictionary") {
				let a = Dependency.gitHub(.dotCom, Repository(owner: "a", name: "a"))
				let b = Dependency.gitHub(.dotCom, Repository(owner: "b", name: "b"))
				let c = Dependency.gitHub(.dotCom, Repository(owner: "c", name: "c"))
				let d = Dependency.gitHub(.dotCom, Repository(owner: "d", name: "d"))
				let e = Dependency.gitHub(.dotCom, Repository(owner: "e", name: "e"))

				let v1 = VersionSpecifier.compatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0))
				let v2 = VersionSpecifier.compatibleWith(SemanticVersion(major: 2, minor: 0, patch: 0))
				let v3 = VersionSpecifier.compatibleWith(SemanticVersion(major: 3, minor: 0, patch: 0))
				let v4 = VersionSpecifier.compatibleWith(SemanticVersion(major: 4, minor: 0, patch: 0))

				let requirements = [a: [b: v1, c: v2], d: [c: v3, e: v4]]
				let invertedRequirements = CompatibilityInfo.invert(requirements: requirements).value
				expect(invertedRequirements) == [b: [a: v1], c: [a: v2, d: v3], e: [d: v4]]
			}
		}
	}
}
