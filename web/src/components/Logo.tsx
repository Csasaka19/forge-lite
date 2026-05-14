interface LogoProps {
  size?: number
  className?: string
}

export function Logo({ size = 32, className = '' }: LogoProps) {
  return (
    <div
      className={`inline-flex items-center justify-center rounded-md bg-primary text-primary-foreground shadow-sm ${className}`}
      style={{ width: size, height: size }}
      aria-label="Forge Lite"
    >
      <span
        className="font-serif italic font-semibold leading-none"
        style={{ fontSize: size * 0.62 }}
      >
        F
      </span>
    </div>
  )
}
