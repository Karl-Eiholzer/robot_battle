import math

class Mat2x2:
    def __init__(self) -> None:
        self.data = [0, 0, 0, 0]
    
    """Constructs a Matrix in column major order"""
    def __init__(self, a00: int | float, a01: int | float, a10: int | float, a11: int | float) -> None:
        self.data = [a00, a01, a10, a11]
    
    def __getitem__(self, i: list[int]) -> int | float:
        return self.data[2 * i[0] + i[1]]
    
    def __setitem__(self, i: list[int], value: int | float) -> None:
        self.data[2 * i[0] + i[1]] = value
    
    def __str__(self) -> str:
        return f"[{self[0, 0]}, {self[0, 1]}]\n[{self[1, 0]}, {self[1, 1]}]"

    def __mul__(self, rhs: list[int | float]) -> tuple[int | float]:
        if(len(rhs) == 2):
            return (self[0, 0] * rhs[0] + self[1, 0] * rhs[1], self[0, 1] * rhs[0] + self[1, 1] * rhs[1])
    
    def __rmul__(self, lhs: list[int | float]) -> tuple[int | float]:
        if(len(lhs) == 2):
            return self * lhs

def rotation2x2(angle: float) -> Mat2x2:
    s = math.sin(angle)
    c = math.cos(angle)
    return Mat2x2(c, s, -s, c)

class Vec2:
    def __init__(self) -> None:
        self.x = 0
        self.y = 0
    
    def __init__(self, l: list[int | float]) -> None:
        self.x = l[0]
        self.y = l[1]

    def __init__(self, x: int | float, y: int | float) -> None:
        self.x = x
        self.y = y

    def __str__(self) -> str:
        return f"<{self.x}, {self.y}>"

    def __tuple__(self) -> tuple:
        return (self.x, self.y)
    
    def __getitem__(self, i: int) -> int | float:
        if i == 0:
            return self.x
        if i == 1:
            return self.y
    
    def __setitem__(self, i: int, value: int | float):
        if i == 0:
            self.x = value
        if i == 1:
            self.y = value
    
    def __len__(self):
        return 2


Q_ROTATION = rotation2x2(math.tau / 3)
# Unit Vector pointing in the Q direction
Q_UNIT = [1, 0] * Q_ROTATION
S_ROTATION = rotation2x2(-math.tau / 3)

S_UNIT = [1, 0] * S_ROTATION
class VecH:
    def __init__(self) -> None:
        self.r = 0
        self.q = 0
        self.s = 0

    def __init__(self, l: list[int | float]) -> None:
        self.r = l[0]
        self.q = l[1]
        self.s = l[2]

    def __init__(self, r: int | float, q: int | float, s: int | float) -> None:
        self.r = r
        self.q = q
        self.s = s
    
    def __str__(self) -> str:
        return f"<r: {self.r}, q: {self.q}, s: {self.s}>"
    
    def __tuple__(self) -> tuple:
        return (self.r, self.q, self.s)

    def __len__(self) -> int:
        return 3
    
    def cartesian(self) -> tuple:
        """ Converts the Vector into a 2d repersentation

        Returns:
            tuple: _description_
        """
        return (self.r + self.q * Q_UNIT[0] + self.s * S_UNIT[0], self.q * Q_UNIT[1] + self.s * S_UNIT[1])
