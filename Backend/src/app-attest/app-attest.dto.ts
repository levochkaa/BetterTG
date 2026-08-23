import { IsBase64, IsString, Length, MaxLength } from 'class-validator'

export class VerifyAttestationDto {
    @IsString()
    @Length(20, 255)
    keyId!: string

    @IsString()
    @Length(20, 128)
    challenge!: string

    @IsBase64()
    @MaxLength(60_000)
    attestation!: string
}
