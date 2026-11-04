// Checks an Ed25519 signature (the kind Sparkle's sign_update makes) against a given public key:
//   swift scripts/verify-ed-signature.swift <file> <signature-base64> <public-key-base64>
// Exit 0: valid. 1: not valid for this key. 2: usage error, or the file, signature or key can't be read.
//
// sign_update --verify can't do this job: it checks against the public key derived from the private
// key it is given, so it would not notice a CI secret that differs from the app's SUPublicEDKey.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fail("usage: verify-ed-signature.swift <file> <signature-base64> <public-key-base64>")
}
guard let data = try? Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe) else {
    fail("error: cannot read \(args[1])")
}
guard let signature = Data(base64Encoded: args[2]) else {
    fail("error: the signature is not base64")
}
guard let keyData = Data(base64Encoded: args[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("error: the public key is not a base64 Ed25519 key")
}
exit(publicKey.isValidSignature(signature, for: data) ? 0 : 1)
