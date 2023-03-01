


import pygame

screen = pygame.display.set_mode((700, 700))

running = True

while running:
    for event in pygame.event.get(): 
        if event.type == pygame.QUIT:
            running = False
        